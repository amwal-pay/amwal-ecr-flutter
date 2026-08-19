import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/foundation.dart';

import '../../data/terminal.dart';
import '../../data/terminal_repository.dart';
import 'transaction_state.dart';

/// Drives the transaction screen.
///
/// Mirrors `TransactionViewModel.kt`, step for step — the order of the checks
/// is the behaviour, not an implementation detail, so it is kept identical to
/// the Android example.
class TransactionController extends ChangeNotifier {
  TransactionController(this._repository);

  final TerminalRepository _repository;

  TransactionState _state = const TransactionIdle();
  TransactionState get state => _state;

  void _emit(TransactionState next) {
    _state = next;
    notifyListeners();
  }

  /// Clears the result so its dialog is shown once and not again on rebuild.
  void resultAcknowledged() => _emit(const TransactionIdle());

  /// Resolves the terminal by serial number and runs the operation against it.
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

    final EcrTerminal terminal = _terminalFor(registered);

    // Nothing is sent until the terminal is known to be listening, so a
    // terminal that is off or on another network fails at once rather than
    // part way into a sale the cashier believes has started.
    if (!await terminal.isReachable()) {
      _emit(TransactionFailed(
        '${registered.ipAddress}:${registered.port} is not reachable.\n'
        'Check that the terminal is switched on, connected to the same '
        'Wi-Fi network, and sitting on its idle screen.',
      ));
      return;
    }

    _emit(const TransactionInProgress());

    // An inquiry answers with the transaction it found rather than one it
    // performed, so it takes its own route out.
    if (request.type == EcrTransactionType.inquiry) {
      final EcrInquiry inquiry = await terminal.inquire(
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
      EcrTransactionType.sale => await terminal.sale(request.amount!),
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
      // Neither is a menu choice: an inquiry is answered above, and a receipt
      // is asked for from the result it belongs to.
      EcrTransactionType.inquiry ||
      EcrTransactionType.receipt =>
        throw StateError('${request.type.displayName} is not run from here'),
    };

    _emit(switch (result) {
      EcrFailed(:final EcrFailure failure) => TransactionFailed(failure.message),
      _ => TransactionCompleted(result, request.type),
    });
  }

  /// Fetches the e-receipt of the transaction the inquiry found.
  ///
  /// Asked for from the result the operator is already looking at, so the
  /// transaction is named by the inquiry's own request rather than re-keyed.
  /// Nothing is charged and nothing changes, so a second press is harmless.
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
          merchantReferenceId: '',
          reason: 'Terminal ${current.request.terminalSerial} '
              'is no longer registered',
          raw: '',
        ),
      ));
      return;
    }

    final EcrReceipt receipt = await _terminalFor(registered).receipt(
      receiptNumber: current.request.receiptNumber,
      transactionDate: current.request.transactionDate,
      originalTerminalId: current.request.originalTerminalId,
    );

    // Read the state again: the operator may have closed the dialog while the
    // backend was publishing the receipt.
    final TransactionState latest = _state;
    if (latest is! TransactionInquired) return;
    _emit(latest.copyWith(receipt: receipt, fetchingReceipt: false));
  }

  EcrTerminal _terminalFor(Terminal terminal) => EcrTerminal(
        host: terminal.ipAddress,
        serialNumber: terminal.serialNumber,
        config: _ecrConfig(terminal.port),
      );

  /// Everything but the port is the same for every terminal this app talks to.
  ///
  /// The key is the one the demo terminals are provisioned with, hardcoded here
  /// exactly as `TransactionViewModel.kt` does it so the two examples talk to
  /// the same terminals. A real till reads it from the keystore/keychain: a
  /// terminal only accepts the key TMS issued for *it*, and a key in source is
  /// a key in every APK and IPA built from it.
  EcrConfig _ecrConfig(int port) =>
      EcrConfig(ecrId: _ecrId, port: port, secureHashKey: _secureHashKey);

  static const String _ecrId = 'ECR01';
  static const String _secureHashKey = '881dc200c9833da726e9376c2e32cff7';
}
