import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/foundation.dart';

import '../../data/ecr_mode.dart';
import '../../data/ecr_simulator_settings.dart';
import '../../data/terminal.dart';
import '../../data/terminal_repository.dart';
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

  Future<void> updateSelectedTerminal(Terminal? terminal) async {
    if (terminal == null) {
      _selectedConfig = null;
      notifyListeners();
      return;
    }
    _selectedConfig = await _resolveConfig(terminal);
    notifyListeners();
  }

  void _emit(TransactionState next) {
    _state = next;
    notifyListeners();
  }

  void resultAcknowledged() => _emit(const TransactionIdle());

  Future<void> startTransaction(TransactionRequest request) async {
    if (_state.isBusy) return;

    _emit(const TransactionChecking());

    final Terminal? registered =
        await _repository.findBySerial(request.terminalSerial);
    if (registered == null) {
      _emit(TransactionFailed(
        'Terminal ${request.terminalSerial} is no longer registered',
      ));
      return;
    }

    final SelectedTerminalConfig active = await _resolveConfig(registered);
    _selectedConfig = active;

    if (!active.isReady) {
      _emit(TransactionFailed(active.issues.join('\n')));
      return;
    }

    final EcrTerminal terminal = _terminalFor(registered, active);

    if (active.usesLan) {
      if (!await terminal.isReachable()) {
        _emit(TransactionFailed(
          '${registered.ipAddress}:${registered.port} is not reachable.\n'
          'Check that the POS app is in ECR mode (Wi‑Fi), the registered IP '
          'and port match, and both devices are on the same network.',
        ));
        return;
      }
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
        ),
      EcrTransactionType.refund => await terminal.refund(
          request.amount!,
          receiptNumber: request.receiptNumber,
          transactionDate: request.transactionDate,
          originalTerminalId: request.originalTerminalId,
        ),
      EcrTransactionType.inquiry ||
      EcrTransactionType.receipt =>
        throw StateError('${request.type.displayName} is not run from here'),
    };

    _emit(switch (result) {
      EcrFailed() => _failureOf(result, request),
      _ => TransactionCompleted(result, request.type),
    });
  }

  TransactionState _failureOf(EcrFailed result, TransactionRequest request) {
    final EcrInquiry? recovered = result.recovered;
    if (recovered is EcrInquiryFound) {
      return TransactionInquired(
        inquiry: recovered,
        request: request.copyWith(
          type: EcrTransactionType.inquiry,
          originalReference: result.merchantReference,
        ),
      );
    }

    return TransactionFailed(
      result.failure.message,
      inquirableReference: result.merchantReference,
    );
  }

  void inquireAboutReference(String reference, String terminalSerial) {
    if (_state.isBusy) return;

    startTransaction(TransactionRequest(
      type: EcrTransactionType.inquiry,
      terminalSerial: terminalSerial,
      amount: null,
      originalReference: reference,
      merchantReference: reference,
    ));
  }

  Future<void> requestReceipt() async {
    final TransactionState current = _state;
    if (current is! TransactionInquired || current.fetchingReceipt) return;

    _emit(current.copyWith(fetchingReceipt: true));

    final Terminal? registered =
        await _repository.findBySerial(current.request.terminalSerial);
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
    if (!active.usesLan) {
      _emit(current.copyWith(
        fetchingReceipt: false,
        receipt: const EcrReceiptUnavailable(
          merchantReference: '',
          reason: 'Receipt fetch is only supported over Wi‑Fi / Ethernet ECR',
          raw: '',
        ),
      ));
      return;
    }

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
          reason: 'This transaction has no receipt number to fetch a receipt by',
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

    final TransactionState latest = _state;
    if (latest is! TransactionInquired) return;
    _emit(latest.copyWith(receipt: receipt, fetchingReceipt: false));
  }

  static String _dayOf(String? transactionTime) {
    final String digits =
        (transactionTime ?? '').replaceAll(RegExp('[^0-9]'), '');
    return digits.length >= 8 ? digits.substring(0, 8) : '';
  }

  EcrTerminal _terminalFor(Terminal terminal, SelectedTerminalConfig active) {
    final EcrTransport transport = switch (terminal.mode) {
      EcrMode.ethernet => EcrTransport.ethernet,
      EcrMode.wifi => EcrTransport.wifi,
      EcrMode.bluetooth => EcrTransport.bluetooth,
      EcrMode.webService => EcrTransport.webService,
    };

    return EcrTerminal(
      host: active.usesLan ? terminal.ipAddress : '',
      serialNumber: terminal.serialNumber,
      transport: transport,
      config: active.ecrConfig,
    );
  }
}
