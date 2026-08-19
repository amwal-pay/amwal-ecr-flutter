import 'dart:math';

import 'ecr_operation.dart';
import 'model/ecr_amount.dart';
import 'model/ecr_config.dart';
import 'model/ecr_errors.dart';
import 'model/ecr_failure.dart';
import 'model/ecr_inquiry.dart';
import 'model/ecr_receipt.dart';
import 'model/ecr_result.dart';
import 'model/ecr_transaction_type.dart';
import 'model/ecr_transport.dart';
import 'platform/amwal_ecr_platform.dart';
import 'platform/ecr_request.dart';

/// A POS terminal reachable over the local network.
///
/// One instance addresses one terminal; it holds no connection between calls,
/// so it is cheap to keep and safe to reuse.
///
/// ```dart
/// final EcrTerminal terminal = EcrTerminal(
///   host: '192.168.1.50',
///   serialNumber: 'P653200085189',
/// );
///
/// switch (await terminal.sale(EcrAmount.parse('1.234'))) {
///   case EcrApproved(:final String amount, :final String rrn):
///     print('Took $amount, RRN $rrn');
///   case EcrDeclined(:final String reason):
///     print('Refused: $reason');
///   case EcrFailed(:final EcrFailure failure):
///     print('No answer: ${failure.message}');
/// }
/// ```
///
/// ## The one rule
///
/// A response that never arrives is **not** a decline. If the socket times out
/// or the connection breaks, the terminal may have completed the payment and
/// been unable to say so. Nothing in this package retries a money-moving
/// request, and neither should a caller: check [EcrResult.outcomeIsUnknown],
/// and where it is set, [inquire] on the receipt number instead.
final class EcrTerminal {
  /// [host] is the terminal's address on the local network, and [serialNumber]
  /// is what the operator registered — the terminal shows its own address on
  /// screen under the card scheme logos when the link is Wi-Fi.
  ///
  /// [transport] declares how the terminal is attached, from its TMS profile.
  /// Only the IP transports can be driven from here; naming another is allowed
  /// and becomes an [EcrUnsupported] failure at the first operation, so a till
  /// reading a profile it does not control handles it as one more outcome
  /// rather than as a crash.
  EcrTerminal({
    required this.host,
    this.serialNumber = '',
    EcrConfig? config,
    this.transport = EcrTransport.wifi,
    AmwalEcrPlatform? platform,
    Random? random,
  })  : config = config ?? EcrConfig(),
        _platform = platform ?? AmwalEcrPlatform.instance,
        _random = random ?? Random() {
    if (host.trim().isEmpty) {
      throw const EcrArgumentError('A terminal needs a host address');
    }
  }

  /// The terminal's address on the local network.
  final String host;

  /// Identifies the terminal in the message.
  final String serialNumber;

  /// How this till identifies itself and how long it waits.
  final EcrConfig config;

  /// How the terminal is attached, from its TMS profile.
  final EcrTransport transport;

  final AmwalEcrPlatform _platform;
  final Random _random;

  /// Whether the terminal is listening.
  ///
  /// Worth calling before a sale: it turns a wrong address or a terminal on
  /// another network into an immediate answer, rather than a failure a
  /// cardholder waits through. It proves the port is open, not that the
  /// terminal is idle — a terminal already taking a payment answers too.
  ///
  /// Answers `false` for a transport that has no listener at all, rather than
  /// spending [EcrConfig.probeTimeout] finding out.
  Future<bool> isReachable() {
    if (!transport.isIpTransport) return Future<bool>.value(false);
    return _platform.isReachable(_request(operationId: _newOperationId()));
  }

  /// Takes a payment. The cardholder presents their card at the terminal.
  ///
  /// [merchantReferenceId] is the till's own reference for this sale — an order
  /// number, a basket id, whatever the caller's system already uses to name it.
  /// Pass it and the same string identifies the transaction in your books, in
  /// the terminal's records and in any later [inquireByReference]; leave it out
  /// and the native SDK generates one, reported on
  /// [EcrResult.merchantReferenceId].
  ///
  /// Worth passing. It is the only handle a till holds if the answer never
  /// arrives — see the note on this class.
  Future<EcrResult> sale(
    EcrAmount amount, {
    String merchantReferenceId = '',
    String? operationId,
  }) =>
      startSale(
        amount,
        merchantReferenceId: merchantReferenceId,
        operationId: operationId,
      ).result;

  /// [sale], with a handle so it can be cancelled while it runs.
  EcrOperation<EcrResult> startSale(
    EcrAmount amount, {
    String merchantReferenceId = '',
    String? operationId,
  }) =>
      startRun(
        EcrTransactionType.sale,
        amount: amount,
        merchantReferenceId: merchantReferenceId,
        operationId: operationId,
      );

  /// Cancels an earlier transaction in full, by the receipt number printed on
  /// it.
  ///
  /// No amount: a void returns exactly what the original took, and only the
  /// terminal knows that figure. No card is presented either — for a
  /// transaction taken on this same terminal it completes in about a second.
  ///
  /// [originalTerminalId] names the terminal the original was taken on, when
  /// it was not this one. That route asks the backend and reads the card again.
  ///
  /// [merchantReferenceId] names the cancellation, not the transaction being
  /// cancelled — that one is named by [receiptNumber].
  Future<EcrResult> voidTransaction(
    String receiptNumber, {
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) =>
      startVoid(
        receiptNumber,
        originalTerminalId: originalTerminalId,
        merchantReferenceId: merchantReferenceId,
        operationId: operationId,
      ).result;

  /// [voidTransaction], with a handle so it can be cancelled while it runs.
  EcrOperation<EcrResult> startVoid(
    String receiptNumber, {
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) =>
      startRun(
        EcrTransactionType.voidTransaction,
        receiptNumber: receiptNumber,
        originalTerminalId: originalTerminalId,
        merchantReferenceId: merchantReferenceId,
        operationId: operationId,
      );

  /// Returns money against an earlier transaction, in full or in part. The
  /// cardholder presents their card to receive it.
  ///
  /// [transactionDate] is the day the original was taken, as `yyyyMMdd` — a
  /// receipt number is only unique within a terminal's day.
  Future<EcrResult> refund(
    EcrAmount amount, {
    required String receiptNumber,
    required String transactionDate,
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) =>
      startRefund(
        amount,
        receiptNumber: receiptNumber,
        transactionDate: transactionDate,
        originalTerminalId: originalTerminalId,
        merchantReferenceId: merchantReferenceId,
        operationId: operationId,
      ).result;

  /// [refund], with a handle so it can be cancelled while it runs.
  EcrOperation<EcrResult> startRefund(
    EcrAmount amount, {
    required String receiptNumber,
    required String transactionDate,
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) =>
      startRun(
        EcrTransactionType.refund,
        amount: amount,
        receiptNumber: receiptNumber,
        transactionDate: transactionDate,
        originalTerminalId: originalTerminalId,
        merchantReferenceId: merchantReferenceId,
        operationId: operationId,
      );

  /// Runs any operation that moves money.
  ///
  /// The typed methods above are the usual way in; this is for a till driving
  /// the type from its own menu. [EcrTransactionType.inquiry] and
  /// [EcrTransactionType.receipt] are not accepted — they report on a
  /// transaction rather than performing one, and answer with their own types
  /// through [inquire] and [receipt].
  ///
  /// Throws [EcrArgumentError] when the operation's own requirements are not
  /// met. Nothing is sent in that case.
  Future<EcrResult> run(
    EcrTransactionType type, {
    EcrAmount? amount,
    String receiptNumber = '',
    String transactionDate = '',
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) =>
      startRun(
        type,
        amount: amount,
        receiptNumber: receiptNumber,
        transactionDate: transactionDate,
        originalTerminalId: originalTerminalId,
        merchantReferenceId: merchantReferenceId,
        operationId: operationId,
      ).result;

  /// [run], with a handle so it can be cancelled while it runs.
  EcrOperation<EcrResult> startRun(
    EcrTransactionType type, {
    EcrAmount? amount,
    String receiptNumber = '',
    String transactionDate = '',
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) {
    if (!type.movesMoney) {
      throw EcrArgumentError(
        '${type.displayName} reports on a transaction rather than performing '
        'one. Run it with ${type == EcrTransactionType.inquiry ? 'inquire()' : 'receipt()'}.',
      );
    }
    if (type.requiresAmount && amount == null) {
      throw EcrArgumentError('${type.displayName} needs an amount');
    }
    if (!type.requiresAmount && amount != null) {
      // A void takes the original's amount. Accepting one here would let a
      // till believe it had voided a part of a transaction.
      throw EcrArgumentError(
        '${type.displayName} takes no amount — it returns exactly what the '
        'original took.',
      );
    }
    if (type.requiresOriginalStan && receiptNumber.trim().isEmpty) {
      throw EcrArgumentError(
        "${type.displayName} needs the original's receipt number",
      );
    }
    _checkDate(transactionDate);
    _checkReference(merchantReferenceId);

    final String id = operationId ?? _newOperationId();
    final EcrRequest request = _request(
      operationId: id,
      amount: amount,
      receiptNumber: receiptNumber,
      transactionDate: transactionDate,
      originalTerminalId: originalTerminalId,
      merchantReferenceId: merchantReferenceId,
    );

    if (!transport.isIpTransport) {
      return _refused(id, _unsupportedTransport(type.displayName));
    }

    return _operation<EcrResult>(
      id,
      switch (type) {
        EcrTransactionType.sale => _platform.sale(request),
        EcrTransactionType.voidTransaction => _platform.voidTransaction(request),
        EcrTransactionType.refund => _platform.refund(request),
        // Unreachable: movesMoney was checked above. Kept so the switch is
        // exhaustive without a default that would hide a new type.
        EcrTransactionType.inquiry ||
        EcrTransactionType.receipt =>
          throw EcrArgumentError('${type.displayName} does not move money'),
      },
    );
  }

  /// Asks what became of an earlier transaction, without touching it.
  ///
  /// Nothing is authorised and no card is presented, so this is safe to repeat
  /// and the terminal answers it even while taking a payment — which is when a
  /// till most needs it. After a timeout the outcome is unknown, and this is
  /// how to find out rather than retry and risk charging twice.
  Future<EcrInquiry> inquire({
    required String receiptNumber,
    required String transactionDate,
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) =>
      startInquire(
        receiptNumber: receiptNumber,
        transactionDate: transactionDate,
        originalTerminalId: originalTerminalId,
        merchantReferenceId: merchantReferenceId,
        operationId: operationId,
      ).result;

  /// [inquire], with a handle. Cancelling one is harmless: nothing changes.
  EcrOperation<EcrInquiry> startInquire({
    required String receiptNumber,
    required String transactionDate,
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) {
    if (receiptNumber.trim().isEmpty) {
      throw const EcrArgumentError('An inquiry needs a receipt number');
    }
    _checkDate(transactionDate);
    _checkReference(merchantReferenceId);

    final String id = operationId ?? _newOperationId();
    if (!transport.isIpTransport) {
      return _refusedInquiry(id, 'Inquiry');
    }

    return _operation<EcrInquiry>(
      id,
      _platform.inquire(
        _request(
          operationId: id,
          receiptNumber: receiptNumber,
          transactionDate: transactionDate,
          originalTerminalId: originalTerminalId,
          merchantReferenceId: merchantReferenceId,
        ),
      ),
    );
  }

  /// Asks what became of the transaction this till named [originalReference],
  /// without touching it.
  ///
  /// **This is the answer to an outcome you never received.** A receipt number
  /// arrives *in* the terminal's answer, so after an [EcrTimeout], an
  /// [EcrConnectionLost], an [EcrCancelled] or an [EcrUnauthenticated] there is
  /// no receipt number to quote — but the reference you sent the request with is
  /// still yours, and that is what this looks the transaction up by.
  ///
  /// ```dart
  /// final EcrResult result = await terminal.sale(
  ///   total,
  ///   merchantReferenceId: order.number,
  /// );
  ///
  /// if (result.outcomeIsUnknown) {
  ///   // Never retry here — find out first.
  ///   switch (await terminal.inquireByReference(order.number)) {
  ///     case EcrInquiryFound(:final EcrTransaction transaction):
  ///       reconcile(transaction);
  ///     case EcrInquiryNotFound():
  ///       // Nothing was taken. Only now is it safe to send the sale again.
  ///     case EcrInquiryFailed():
  ///       // Still unknown. Ask again later; do not retry the sale.
  ///   }
  /// }
  /// ```
  ///
  /// The host already asks this for you on a lost money-moving request — see
  /// `EcrConfig.autoInquireOnFailure` and [EcrFailed.recovered]. This method is
  /// for asking again later, and for a till that turned that off.
  ///
  /// Nothing is authorised and no card is presented, so it is safe to repeat and
  /// the terminal answers it even while taking a payment.
  ///
  /// [transactionDate] is optional here: a reference is not scoped to a day the
  /// way a receipt number is.
  Future<EcrInquiry> inquireByReference(
    String originalReference, {
    String transactionDate = '',
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) =>
      startInquireByReference(
        originalReference,
        transactionDate: transactionDate,
        originalTerminalId: originalTerminalId,
        merchantReferenceId: merchantReferenceId,
        operationId: operationId,
      ).result;

  /// [inquireByReference], with a handle. Cancelling one is harmless.
  EcrOperation<EcrInquiry> startInquireByReference(
    String originalReference, {
    String transactionDate = '',
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) {
    if (originalReference.trim().isEmpty) {
      throw const EcrArgumentError(
        "An inquiry by reference needs the original's reference",
      );
    }
    _checkDate(transactionDate);
    _checkReference(originalReference);
    _checkReference(merchantReferenceId);

    final String id = operationId ?? _newOperationId();
    if (!transport.isIpTransport) {
      return _refusedInquiry(id, 'Inquiry by reference');
    }

    return _operation<EcrInquiry>(
      id,
      _platform.inquireByReference(
        _request(
          operationId: id,
          transactionDate: transactionDate,
          originalTerminalId: originalTerminalId,
          merchantReferenceId: merchantReferenceId,
          originalMerchantReference: originalReference.trim(),
        ),
      ),
    );
  }

  /// Fetches an earlier transaction's e-receipt.
  ///
  /// Answers with a URL to put in a QR code: the customer scans it and reads
  /// the receipt on their own phone, so a till with no printer can still hand
  /// one over. Non-financial and reprintable — ask as often as you like,
  /// including while the terminal is busy.
  Future<EcrReceipt> receipt({
    required String receiptNumber,
    required String transactionDate,
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) =>
      startReceipt(
        receiptNumber: receiptNumber,
        transactionDate: transactionDate,
        originalTerminalId: originalTerminalId,
        merchantReferenceId: merchantReferenceId,
        operationId: operationId,
      ).result;

  /// [receipt], with a handle. Cancelling one is harmless: nothing changes.
  EcrOperation<EcrReceipt> startReceipt({
    required String receiptNumber,
    required String transactionDate,
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String? operationId,
  }) {
    if (receiptNumber.trim().isEmpty) {
      throw const EcrArgumentError('A receipt needs a receipt number');
    }
    _checkDate(transactionDate);
    _checkReference(merchantReferenceId);

    final String id = operationId ?? _newOperationId();
    if (!transport.isIpTransport) {
      return _refusedWith<EcrReceipt>(
        id,
        (EcrFailure failure) =>
            EcrReceiptFailed(merchantReferenceId: '', failure: failure),
        _unsupportedTransport('Receipt'),
      );
    }

    return _operation<EcrReceipt>(
      id,
      _platform.receipt(
        _request(
          operationId: id,
          receiptNumber: receiptNumber,
          transactionDate: transactionDate,
          originalTerminalId: originalTerminalId,
          merchantReferenceId: merchantReferenceId,
        ),
      ),
    );
  }

  /// Asks the host to abandon the operation with [operationId].
  ///
  /// Usually reached through [EcrOperation.cancel]; this form is for a till
  /// that kept the id rather than the handle.
  Future<bool> cancel(String operationId) => _platform.cancel(operationId);

  EcrRequest _request({
    required String operationId,
    EcrAmount? amount,
    String receiptNumber = '',
    String transactionDate = '',
    String originalTerminalId = '',
    String merchantReferenceId = '',
    String originalMerchantReference = '',
  }) =>
      EcrRequest(
        operationId: operationId,
        host: host,
        serialNumber: serialNumber,
        transport: transport,
        config: config,
        amount: amount,
        receiptNumber: receiptNumber,
        transactionDate: transactionDate,
        originalTerminalId: originalTerminalId,
        merchantReferenceId: merchantReferenceId,
        originalMerchantReference: originalMerchantReference,
      );

  EcrOperation<T> _operation<T extends Object>(String id, Future<T> result) =>
      EcrOperation<T>(
        operationId: id,
        result: result,
        onCancel: _platform.cancel,
      );

  /// An operation that was refused here and never reached the host, so its
  /// cancel has nothing to cancel.
  EcrOperation<EcrResult> _refused(String id, EcrFailure failure) =>
      _refusedWith<EcrResult>(
        id,
        (EcrFailure failure) =>
            EcrFailed(merchantReferenceId: '', failure: failure),
        failure,
      );

  /// A lookup refused here, because the transport has no listener to ask.
  EcrOperation<EcrInquiry> _refusedInquiry(String id, String operation) =>
      _refusedWith<EcrInquiry>(
        id,
        (EcrFailure failure) =>
            EcrInquiryFailed(merchantReferenceId: '', failure: failure),
        _unsupportedTransport(operation),
      );

  EcrOperation<T> _refusedWith<T extends Object>(
    String id,
    T Function(EcrFailure failure) wrap,
    EcrFailure failure,
  ) =>
      EcrOperation<T>(
        operationId: id,
        result: Future<T>.value(wrap(failure)),
        onCancel: (String _) async => false,
      );

  EcrUnsupported _unsupportedTransport(String operation) => EcrUnsupported(
        '$operation is not available over ${transport.name}. '
        'A terminal opens its ECR listener only for the IP transports '
        '(ethernet, wifi); on ${transport.name} the port stays closed and the '
        'terminal is driven by other machinery entirely.',
      );

  /// A date the protocol can carry, or nothing at all.
  ///
  /// Absence is allowed — the native SDKs leave the field out rather than
  /// refusing — but a date in some other shape is always a bug, and one that
  /// surfaces as "transaction not found" hours later if it is let through.
  static void _checkDate(String date) {
    if (date.isEmpty) return;
    if (!_yyyymmdd.hasMatch(date)) {
      throw EcrArgumentError(
        'transactionDate must be yyyyMMdd, e.g. "20260809" — got "$date"',
      );
    }
  }

  static final RegExp _yyyymmdd = RegExp(r'^\d{8}$');

  /// A reference the wire format can carry, or nothing at all.
  ///
  /// Checked here as well as by the native SDK so a till is told before the
  /// channel hop, with the same message on both platforms. The rules are the
  /// protocol's: at most 32 characters of printable ASCII, and never a space,
  /// `&` or `=` — those are the separators a signed message is built from, and a
  /// reference carrying one could make two different messages hash alike.
  static void _checkReference(String reference) {
    final String trimmed = reference.trim();
    if (trimmed.isEmpty) return;

    if (trimmed.length > _referenceMaxLength) {
      throw EcrArgumentError(
        'A merchant reference is at most $_referenceMaxLength characters, '
        'was ${trimmed.length}',
      );
    }
    if (!_printableAscii.hasMatch(trimmed)) {
      throw EcrArgumentError(
        "A merchant reference takes printable ASCII without spaces, '&' or "
        '\'=\': was "$trimmed"',
      );
    }
  }

  /// The longest reference the terminal will carry.
  static const int _referenceMaxLength = 32;

  /// 0x21..0x7E is printable ASCII with the space left out, less `&` and `=`.
  static final RegExp _printableAscii = RegExp(r'^[\x21-\x25\x27-\x3C\x3E-\x7E]+$');

  /// A handle for one call: time-ordered, so a log reads in the order things
  /// happened, plus randomness so two tills cannot collide.
  String _newOperationId() {
    final int now = DateTime.now().microsecondsSinceEpoch;
    final int salt = _random.nextInt(1 << 32);
    return '${now.toRadixString(36)}-${salt.toRadixString(36)}';
  }
}
