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
      final EcrInquiry inquiry = request.looksUpByReference
          // The route that works after an answer that never arrived: the
          // reference is the only identifier this till still has.
          ? await terminal.inquireByReference(
              request.originalReference,
              transactionDate: request.transactionDate,
              originalTerminalId: request.originalTerminalId,
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
      EcrFailed() => _failureOf(result, request),
      _ => TransactionCompleted(result, request.type),
    });
  }

  /// What to show for an exchange that failed.
  ///
  /// The SDK follows a lost answer with an inquiry of its own, so by the time
  /// this runs the outcome is often already known. Showing "unknown" anyway —
  /// and asking the operator to press a button that repeats a question already
  /// answered — would waste the recovery entirely.
  TransactionState _failureOf(EcrFailed result, TransactionRequest request) {
    final EcrInquiry? recovered = result.recovered;
    if (recovered is EcrInquiryFound) {
      // The delivery failed; the transaction did not. Show what happened.
      return TransactionInquired(
        inquiry: recovered,
        request: request.copyWith(
          type: EcrTransactionType.inquiry,
          originalReference: result.merchantReferenceId,
        ),
      );
    }

    return TransactionFailed(
      result.failure.message,
      // Still unknown. Offer the one action that is not a second charge — the
      // automatic attempt may simply have run while the network was still down.
      inquirableReference: result.merchantReferenceId,
    );
  }

  /// Looks up the transaction that this till named [reference], after an
  /// outcome that never arrived.
  ///
  /// Reached from the failure dialog rather than re-keyed, because the whole
  /// point is that the operator has nothing else to type: the receipt number
  /// was in the answer that went missing.
  void inquireAboutReference(String reference, String terminalSerial) {
    if (_state.isBusy) return;

    startTransaction(TransactionRequest(
      type: EcrTransactionType.inquiry,
      terminalSerial: terminalSerial,
      amount: null,
      originalReference: reference,
    ));
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

    // Taken from the transaction the inquiry found, not from the request. A
    // lookup by reference carries no receipt number — that is the whole reason
    // for looking up by reference — and the found transaction is where the
    // number came back.
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
          merchantReferenceId: '',
          reason: 'This transaction has no receipt number to fetch a receipt by',
          raw: '',
        ),
      ));
      return;
    }

    // And the day it was taken, from the same place. A receipt number is only
    // unique within a terminal's day, so asking without the date invites the
    // terminal to answer about a different transaction that happens to share
    // the number.
    final String transactionDate = switch (_dayOf(found?.transactionTime)) {
      final String day when day.isNotEmpty => day,
      _ => current.request.transactionDate,
    };

    final EcrReceipt receipt = await _terminalFor(registered).receipt(
      receiptNumber: receiptNumber,
      transactionDate: transactionDate,
      originalTerminalId: current.request.originalTerminalId,
    );

    // Read the state again: the operator may have closed the dialog while the
    // backend was publishing the receipt.
    final TransactionState latest = _state;
    if (latest is! TransactionInquired) return;
    _emit(latest.copyWith(receipt: receipt, fetchingReceipt: false));
  }

  /// The `yyyyMMdd` day out of a terminal timestamp, or empty if there is not
  /// one in there.
  static String _dayOf(String? transactionTime) {
    final String digits =
        (transactionTime ?? '').replaceAll(RegExp('[^0-9]'), '');
    return digits.length >= 8 ? digits.substring(0, 8) : '';
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
