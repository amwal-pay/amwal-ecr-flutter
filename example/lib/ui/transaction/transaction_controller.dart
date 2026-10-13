import 'dart:async';

import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/foundation.dart';

import '../../data/ecr_mode.dart';
import '../../data/ecr_simulator_settings.dart';
import '../../data/terminal.dart';
import '../../data/terminal_repository.dart';
import '../../data/terminal_sessions.dart';
import '../../print/operation_receipt_image.dart';
import '../status/terminal_sign_on_state.dart';
import 'selected_terminal_config.dart';
import 'transaction_state.dart';

class TransactionController extends ChangeNotifier {
  TransactionController(this._repository);

  final TerminalRepository _repository;
  EcrSimulatorSettings? _settings;

  TransactionState _state = const TransactionIdle();
  TransactionState get state => _state;

  SelectedTerminalConfig? _selectedConfig;
  SelectedTerminalConfig? get selectedConfig => _selectedConfig;

  OperationTimer? _operationTimer;
  /// Countdown while a terminal operation is in flight; null when idle.
  OperationTimer? get operationTimer => _operationTimer;

  Timer? _countdownTicker;

  /// Bumped on each new operation or cancel so a late await cannot overwrite
  /// the cancelled / superseded outcome.
  int _operationEpoch = 0;

  static const String operationCancelledMessage = 'Operation cancelled';

  bool get isOperationCancellable {
    final TransactionState current = _state;
    return current.isBusy ||
        (current is TransactionInquired && current.fetchingReceipt);
  }

  Future<void> _ensureSettings() async {
    _settings ??= await EcrSimulatorSettings.load();
  }

  Future<SelectedTerminalConfig> _resolveConfig(Terminal terminal) async {
    await _ensureSettings();
    final EcrSimulatorSettings settings = _settings!;
    return SelectedTerminalConfig.resolve(
      terminal: terminal,
      environment: settings.environment,
      secureHashKey: settings.secureHashKeyFor(terminal.mode),
    );
  }

  /// The serial of the terminal selected in the dropdown, if any.
  String? _selectedSerial;

  /// What the selected terminal last said it would accept, or null when it has
  /// not been asked yet or could not answer.
  ///
  /// Held for the life of the screen and never written to storage. A profile
  /// saved on disk is one a till would build tomorrow's screen from before
  /// asking whether it is still true, which is the mistake this whole
  /// mechanism exists to prevent.
  ///
  /// The single source for everything on screen about this terminal — the
  /// status line, the permitted operations, the dropdown. Anything derived
  /// from a second copy would go on showing the old answer after this one
  /// was corrected.
  TerminalSignOnState? _signOn;
  TerminalSignOnState? get signOn => _signOn;

  /// The operations to offer, narrowed to what the terminal permits.
  ///
  /// Falls back to the whole menu until a sign-on has answered: a terminal that
  /// cannot be reached is not a terminal that permits nothing, and greying out
  /// every button would read as a broken till rather than an unanswered one.
  List<EcrTransactionType> get availableTypes {
    final EcrTerminalCapabilities? known = _signOn.terminalCapabilities;
    if (known == null) return EcrTransactionType.menuOptions;
    final List<EcrTransactionType> permitted = EcrTransactionType.menuOptions
        .where(known.permits)
        .toList(growable: false);
    return permitted.isEmpty ? EcrTransactionType.menuOptions : permitted;
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _operationEpoch++;
    _clearOperationCountdown();
    super.dispose();
  }

  int _responseTimeoutSeconds(SelectedTerminalConfig? config) {
    final int? fromConfig = config?.ecrConfig.responseTimeout.inSeconds;
    final int total = fromConfig ?? 120;
    return total < 1 ? 1 : total;
  }

  void _startOperationCountdown(int totalSeconds) {
    _countdownTicker?.cancel();
    final int total = totalSeconds < 1 ? 1 : totalSeconds;
    _operationTimer = OperationTimer(
      remainingSeconds: total,
      totalSeconds: total,
    );
    notifyListeners();
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final OperationTimer? current = _operationTimer;
      if (current == null) return;
      final int left = current.remainingSeconds - 1;
      _operationTimer = OperationTimer(
        remainingSeconds: left < 0 ? 0 : left,
        totalSeconds: current.totalSeconds,
      );
      notifyListeners();
      if (left <= 0) _countdownTicker?.cancel();
    });
  }

  void _clearOperationCountdown() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
    if (_operationTimer != null) {
      _operationTimer = null;
      notifyListeners();
    }
  }

  /// Stops waiting on the in-flight operation and hides the Cancel button.
  ///
  /// This abandons the till's wait; the terminal / Hub may still finish the
  /// payment — inquire by merchant reference if the outcome matters.
  void cancelOperation() {
    final TransactionState current = _state;
    if (!isOperationCancellable) return;

    _operationEpoch++;
    _clearOperationCountdown();

    if (current is TransactionInquired && current.fetchingReceipt) {
      _emit(current.copyWith(fetchingReceipt: false));
      return;
    }

    _emit(const TransactionFailed(operationCancelledMessage));
  }

  @override
  void notifyListeners() {
    // Answers arrive from the network after the screen may have gone.
    if (!_disposed) super.notifyListeners();
  }

  /// Selects [terminal] and, where that is cheap, asks what it will accept.
  Future<void> updateSelectedTerminal(Terminal? terminal) async {
    if (terminal == null) {
      _selectedSerial = null;
      _selectedConfig = null;
      _signOn = null;
      notifyListeners();
      return;
    }

    final bool changed = _selectedSerial != terminal.serialNumber;
    _selectedSerial = terminal.serialNumber;
    _selectedConfig = await _resolveConfig(terminal);

    // Not for the payment app on this device. Over a socket a sign-on is
    // invisible — a few bytes, and the operator sees nothing. Here every
    // exchange puts the payment app on screen, so asking automatically would
    // mean opening it the moment somebody picks a terminal from a dropdown. It
    // is asked by the transaction instead, where the operator is expecting a
    // payment screen anyway. Web Service has no sign-on at all.
    if (!TerminalSessions.asksSignOn(terminal)) {
      _signOn = null;
      notifyListeners();
      return;
    }
    if (changed) _signOn = null;
    notifyListeners();
    await signOnTo(terminal);
  }

  /// Asks a terminal what it will accept, and narrows the form to the answer.
  ///
  /// Run when a terminal is selected rather than once when it is registered. A
  /// profile read at registration stops being true the first time the merchant
  /// changes anything, and the operator would go on being offered a refund the
  /// terminal now refuses.
  Future<void> signOnTo(Terminal terminal) async {
    final SelectedTerminalConfig active = await _resolveConfig(terminal);
    if (!active.isReady) {
      // Answered here rather than on the wire: there is nothing to ask when
      // the address or the key is missing, and reporting it as a failed
      // exchange would send somebody to look at a network when the problem is
      // on the terminal's own settings screen.
      _setSignOn(
        terminal,
        TerminalNotReady(
          reason: active.issues.isEmpty
              ? 'This terminal is not configured'
              : active.issues.join('\n'),
          capabilities: const EcrTerminalCapabilities(),
        ),
      );
      return;
    }
    await _refreshCapabilities(terminal, _terminalFor(terminal, active));
  }

  /// Asks the terminal to describe itself, and records what it said.
  Future<void> _refreshCapabilities(
    Terminal terminal,
    EcrTerminal session,
  ) async {
    _setSignOn(terminal, const TerminalAsking());

    // One assignment, whatever came back. A failure lands as no-answer and
    // takes the previous picture with it, which is the point: a till acting on
    // what a terminal said before it stopped answering is worse than a till
    // that admits it does not know.
    _setSignOn(terminal, TerminalSignOnState.of(await session.signOn()));
  }

  /// Records an answer only if the terminal is still the one selected, so a
  /// slow answer for the previous choice cannot narrow the next one's form.
  void _setSignOn(Terminal terminal, TerminalSignOnState next) {
    if (_selectedSerial != terminal.serialNumber) return;
    _signOn = next;
    notifyListeners();
  }

  void _emit(TransactionState next) {
    _state = next;
    notifyListeners();
  }

  void resultAcknowledged() {
    _clearOperationCountdown();
    _emit(const TransactionIdle());
    _closeTerminalReceipt();
  }

  /// Tells the terminal the cashier has finished, so it can put its receipt
  /// away and be ready for the next transaction.
  ///
  /// The terminal leaves its receipt up until somebody dismisses it, and when a
  /// till drove the transaction nobody is standing there to do it. Closing the
  /// result dialog is that moment, so this goes with acknowledging it.
  ///
  /// Deliberately silent. The dialog has already gone, and a till that cannot
  /// tidy the terminal's screen has not failed at anything the cashier needs to
  /// hear about: an older terminal, or a Web Service one, refuses and the
  /// receipt stays up exactly as it always did.
  Future<void> _closeTerminalReceipt() async {
    final String? serial = _selectedSerial;
    if (serial == null) return;

    final Terminal? registered = await _repository.findBySerial(serial);
    // Never for the payment app on this device, and not because it would fail
    // — because it has already happened. An app-to-app answer is held until the
    // operator closes the receipt, so by the time the till has a result the
    // terminal is back on its idle screen.
    if (registered == null || registered.mode == EcrMode.appToApp) return;

    try {
      final SelectedTerminalConfig active = await _resolveConfig(registered);
      await _terminalFor(registered, active).closeReceipt();
    } catch (_) {
      // Nothing the cashier needs to hear about; see above.
    }
  }

  Future<void> startTransaction(TransactionRequest request) async {
    if (_state.isBusy) return;

    final int epoch = ++_operationEpoch;
    _startOperationCountdown(_responseTimeoutSeconds(_selectedConfig));
    _emit(const TransactionChecking());

    try {
      final Terminal? registered =
          await _repository.findBySerial(request.terminalSerial);
      if (!_stillCurrent(epoch)) return;
      if (registered == null) {
        _emit(TransactionFailed(
          'Terminal ${request.terminalSerial} is no longer registered',
        ));
        return;
      }

      final SelectedTerminalConfig active = await _resolveConfig(registered);
      if (!_stillCurrent(epoch)) return;
      _selectedConfig = active;

      if (!active.isReady) {
        _emit(TransactionFailed(active.issues.join('\n')));
        return;
      }

      // Align budget if Web Service (130s) differs from the first guess.
      final int timeout = _responseTimeoutSeconds(active);
      if (_operationTimer?.totalSeconds != timeout) {
        _startOperationCountdown(timeout);
      }

      final EcrTerminal terminal = _terminalFor(registered, active);

      if (active.usesLocalTerminal) {
        final EcrReachability probe = await terminal.probeReachability();
        if (!_stillCurrent(epoch)) return;
        if (!probe.reachable) {
          final String message = (StringBuffer()
                ..write('${probe.endpoint} is not reachable')
                ..write(probe.error == null ? '' : '\n(${probe.error})')
                ..write('\n\n')
                ..write(
                  active.usesPaymentApp
                      ? 'Check:\n'
                          '• The Amwal payment app is installed on this device\n'
                          '• It is a build that accepts app-to-app requests\n'
                          '• The merchant is signed in — open it once and sign in\n'
                          '• The application ID matches (${probe.endpoint})\n'
                          '• Serial number matches the terminal this app drives'
                      : active.usesUsbCable
                      ? 'Check:\n'
                          '• The USB cable is connected to the terminal\n'
                          '• POS app is in ECR mode (USB cable) and says it is waiting\n'
                          '• Serial number matches the terminal you selected\n'
                          '• This device can act as a USB host (OTG)'
                      : 'Check:\n'
                          '• POS app is in ECR mode (Wi‑Fi) and shows its IP under the card logos\n'
                          '• Registered IP matches that address (port ${probe.port})\n'
                          '• Serial number matches the terminal you selected\n'
                          '• Both devices are on the same Wi‑Fi network\n'
                          '• If testing on one phone, try IP 127.0.0.1',
                ))
              .toString();
          _emit(TransactionFailed(message));
          return;
        }
      }

      // The terminal was not reachable when it was selected, or has not been
      // asked since, so this is the first chance to learn what it permits. Asking
      // here rather than refusing the request keeps selection independent of the
      // network: a till picks a terminal it cannot see, and finds out what it
      // will accept the first time it tries to use it.
      //
      // Skipped for the payment app on this device, where a sign-on is not free:
      // it is a second handover, so the operator would watch that app open, close
      // and open again for one sale.
      if (_signOn.terminalCapabilities == null &&
          TerminalSessions.asksSignOn(registered)) {
        await _refreshCapabilities(registered, terminal);
        if (!_stillCurrent(epoch)) return;
      }

      _emit(const TransactionInProgress());

      if (request.type == EcrTransactionType.inquiry) {
        final EcrInquiry inquiry = request.looksUpByReference
            ? await terminal.inquireByReference(
                request.originalReference,
                transactionDate: request.transactionDate,
                originalTerminalId: request.originalTerminalId,
                merchantReference: request.merchantReference,
              )
            : await terminal.inquire(
                receiptNumber: request.receiptNumber,
                transactionDate: request.transactionDate,
                originalTerminalId: request.originalTerminalId,
              );
        if (!_stillCurrent(epoch)) return;
        _emit(switch (inquiry) {
          EcrInquiryFailed(:final EcrFailure failure) =>
            TransactionFailed(failure.message),
          _ => TransactionInquired(inquiry: inquiry, request: request),
        });
        return;
      }

      final EcrResult result = switch (request.type) {
        EcrTransactionType.sale => await terminal.sale(
            request.amount!,
            merchantReference: request.merchantReference,
          ),
        EcrTransactionType.voidTransaction => await terminal.voidTransaction(
            request.receiptNumber,
            originalTerminalId: request.originalTerminalId,
            merchantReference: request.merchantReference,
          ),
        EcrTransactionType.refund => await terminal.refund(
            request.amount!,
            receiptNumber: request.receiptNumber,
            transactionDate: request.transactionDate,
            originalTerminalId: request.originalTerminalId,
            merchantReference: request.merchantReference,
          ),
        EcrTransactionType.inquiry ||
        EcrTransactionType.receipt ||
        EcrTransactionType.signOn ||
        EcrTransactionType.closeReceipt =>
          throw StateError('${request.type.displayName} is not run from here'),
      };

      if (!_stillCurrent(epoch)) return;
      _emit(switch (result) {
        EcrFailed() => _failureOf(result, request),
        // Timeout / unknown-outcome envelopes map to Failed so they are not
        // shown as a plain decline.
        EcrDeclined(:final EcrNextStep nextStep, :final String reason)
            when nextStep == EcrNextStep.inquireByMerchantReference =>
          TransactionFailed(reason),
        _ => TransactionCompleted(result, request.type),
      });
    } finally {
      if (!_state.isBusy) _clearOperationCountdown();
    }
  }

  bool _stillCurrent(int epoch) => epoch == _operationEpoch;

  TransactionState _failureOf(EcrFailed result, TransactionRequest request) {
    final EcrInquiry? recovered = result.recovered;
    if (recovered is EcrInquiryFound) {
      return TransactionInquired(
        inquiry: recovered,
        request: request.copyWith(
          type: EcrTransactionType.inquiry,
          originalReference: result.merchantReference,
          merchantReference: '',
        ),
      );
    }

    return TransactionFailed(result.failure.message);
  }

  Future<void> requestReceipt() async {
    final TransactionState current = _state;
    if (current is! TransactionInquired || current.fetchingReceipt) return;

    final int epoch = ++_operationEpoch;
    _startOperationCountdown(_responseTimeoutSeconds(_selectedConfig));
    _emit(current.copyWith(fetchingReceipt: true));

    try {
      final Terminal? registered =
          await _repository.findBySerial(current.request.terminalSerial);
      if (!_stillCurrent(epoch)) return;
      if (registered == null) {
        _emit(current.copyWith(
          fetchingReceipt: false,
          receipt: EcrReceiptUnavailable(
            merchantReference: '',
            reason: 'Terminal ${current.request.terminalSerial} '
                'is no longer registered',
            raw: '',
          ),
        ));
        return;
      }

      final SelectedTerminalConfig active = await _resolveConfig(registered);
      if (!_stillCurrent(epoch)) return;
      if (!active.usesLocalTerminal) {
        _emit(current.copyWith(
          fetchingReceipt: false,
          receipt: const EcrReceiptUnavailable(
            merchantReference: '',
            reason: 'Receipt fetch is only supported over Wi‑Fi / USB cable ECR',
            raw: '',
          ),
        ));
        return;
      }

      _startOperationCountdown(_responseTimeoutSeconds(active));

      final EcrInquiry inquiry = current.inquiry;
      final EcrTransaction? found =
          inquiry is EcrInquiryFound ? inquiry.transaction : null;

      final String receiptNumber = switch (found?.stan) {
        final String stan when stan.trim().isNotEmpty => stan,
        _ => current.request.receiptNumber,
      };

      if (receiptNumber.trim().isEmpty) {
        _emit(current.copyWith(
          fetchingReceipt: false,
          receipt: const EcrReceiptUnavailable(
            merchantReference: '',
            reason:
                'This transaction has no receipt number to fetch a receipt by',
            raw: '',
          ),
        ));
        return;
      }

      final String transactionDate = switch (_dayOf(found?.transactionTime)) {
        final String day when day.isNotEmpty => day,
        _ => current.request.transactionDate,
      };

      final EcrReceipt receipt = await _terminalFor(registered, active).receipt(
        receiptNumber: receiptNumber,
        transactionDate: transactionDate,
        originalTerminalId: current.request.originalTerminalId,
      );

      if (!_stillCurrent(epoch)) return;
      final TransactionState latest = _state;
      if (latest is! TransactionInquired) return;
      _emit(latest.copyWith(receipt: receipt, fetchingReceipt: false));
    } finally {
      _clearOperationCountdown();
    }
  }

  static String _dayOf(String? transactionTime) {
    final String digits =
        (transactionTime ?? '').replaceAll(RegExp('[^0-9]'), '');
    return digits.length >= 8 ? digits.substring(0, 8) : '';
  }

  /// Asks the payment app to print a receipt image built from this operation's
  /// result (not a reprint of the payment app's last stored transaction).
  ///
  /// Only for app-to-app. Other transports return null without calling the
  /// host — the Print button is not shown for them either.
  Future<EcrPrintOutcome?> printReceiptOnPaymentApp(
    EcrApproved result,
    EcrTransactionType type,
  ) async {
    final SelectedTerminalConfig? active = _selectedConfig;
    if (active == null || !active.usesPaymentApp) return null;

    final String? serial = _selectedSerial;
    if (serial == null) return null;
    final Terminal? registered = await _repository.findBySerial(serial);
    if (registered == null || registered.mode != EcrMode.appToApp) {
      return null;
    }

    final Uint8List imagePng =
        await OperationReceiptImage.png(result, type);
    return _terminalFor(registered, active).printReceipt(
      imagePng: imagePng,
      merchantReference: result.merchantReference,
    );
  }

  EcrTerminal _terminalFor(Terminal terminal, SelectedTerminalConfig active) =>
      TerminalSessions.open(terminal, active);
}
