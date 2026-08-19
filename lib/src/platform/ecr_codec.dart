import '../model/ecr_failure.dart';
import '../model/ecr_inquiry.dart';
import '../model/ecr_next_step.dart';
import '../model/ecr_receipt.dart';
import '../model/ecr_result.dart';
import '../model/ecr_transaction.dart';
import 'ecr_channel_contract.dart';

/// Turns the maps the host returns into the typed results callers see.
///
/// Deliberately separate from the channel itself so the mapping can be tested
/// against captured payloads without a binding, and so a contract test can
/// assert what happens to a map that is wrong in every way a real host might
/// get it wrong: a missing field, a null where a string was promised, an
/// outcome this version has never heard of.
///
/// The rule throughout: **never invent an outcome.** A payload that cannot be
/// read becomes an [EcrMalformed] failure, which leaves the financial outcome
/// unknown, rather than a decline — because a till that reads an unreadable
/// answer as a refusal will retry, and the customer pays twice.
abstract final class EcrCodec {
  /// Reads the answer to a sale, void or refund.
  static EcrResult result(Object? payload, {required String operationId}) {
    final Map<Object?, Object?>? map = _asMap(payload);
    if (map == null) return _unreadable(payload, 'a transaction result');

    final String reference = _string(map, EcrResultKeys.merchantReferenceId);

    switch (_string(map, EcrResultKeys.outcome)) {
      case EcrOutcomes.approved:
        return EcrApproved(
          merchantReferenceId: reference,
          amount: _string(map, EcrResultKeys.amount),
          responseCode: _string(map, EcrResultKeys.responseCode),
          rrn: _string(map, EcrResultKeys.rrn),
          authCode: _string(map, EcrResultKeys.authCode),
          maskedPan: _string(map, EcrResultKeys.maskedPan),
          partialApproval: _bool(map, EcrResultKeys.partialApproval),
          requestedAmount: _string(map, EcrResultKeys.requestedAmount),
          raw: _string(map, EcrResultKeys.raw),
        );
      case EcrOutcomes.declined:
        return EcrDeclined(
          merchantReferenceId: reference,
          responseCode: _string(map, EcrResultKeys.responseCode),
          reason: _string(map, EcrResultKeys.responseMessage),
          nextStep: EcrNextStep.parse(map[EcrResultKeys.nextStep] as String?),
          raw: _string(map, EcrResultKeys.raw),
        );
      case EcrOutcomes.failed:
        return EcrFailed(
          merchantReferenceId: reference,
          failure: failure(map[EcrResultKeys.failure]),
          recovered: _recovered(map[EcrResultKeys.recovered], operationId),
        );
      case final String unknown:
        return EcrFailed(
          merchantReferenceId: reference,
          failure: EcrMalformed(_unknownOutcome(unknown, 'a transaction')),
        );
    }
  }

  /// Reads the answer to an inquiry.
  static EcrInquiry inquiry(Object? payload, {required String operationId}) {
    final Map<Object?, Object?>? map = _asMap(payload);
    if (map == null) {
      return EcrInquiryFailed(
        merchantReferenceId: '',
        failure: EcrMalformed(_notAMap(payload, 'an inquiry')),
      );
    }

    final String reference = _string(map, EcrResultKeys.merchantReferenceId);

    switch (_string(map, EcrResultKeys.outcome)) {
      case EcrOutcomes.found:
        final Map<Object?, Object?>? data =
            _asMap(map[EcrResultKeys.transaction]);
        if (data == null) {
          // The host said "found" and sent nothing to show for it. Reporting a
          // transaction of empty strings would be worse than saying so.
          return EcrInquiryFailed(
            merchantReferenceId: reference,
            failure: const EcrMalformed(
              'The host reported a found transaction with no transaction data',
            ),
          );
        }
        return EcrInquiryFound(
          merchantReferenceId: reference,
          transaction: transaction(data),
          raw: _string(map, EcrResultKeys.raw),
        );
      case EcrOutcomes.notFound:
        return EcrInquiryNotFound(
          merchantReferenceId: reference,
          reason: _string(map, EcrResultKeys.responseMessage),
          raw: _string(map, EcrResultKeys.raw),
        );
      case EcrOutcomes.failed:
        return EcrInquiryFailed(
          merchantReferenceId: reference,
          failure: failure(map[EcrResultKeys.failure]),
        );
      case final String unknown:
        return EcrInquiryFailed(
          merchantReferenceId: reference,
          failure: EcrMalformed(_unknownOutcome(unknown, 'an inquiry')),
        );
    }
  }

  /// Reads the answer to a receipt request.
  static EcrReceipt receipt(Object? payload, {required String operationId}) {
    final Map<Object?, Object?>? map = _asMap(payload);
    if (map == null) {
      return EcrReceiptFailed(
        merchantReferenceId: '',
        failure: EcrMalformed(_notAMap(payload, 'a receipt')),
      );
    }

    final String reference = _string(map, EcrResultKeys.merchantReferenceId);

    switch (_string(map, EcrResultKeys.outcome)) {
      case EcrOutcomes.ready:
        final String url = _string(map, EcrResultKeys.url);
        if (url.isEmpty) {
          // A receipt with no URL is not a receipt, whatever the host called
          // it. The native SDKs apply the same rule.
          return EcrReceiptUnavailable(
            merchantReferenceId: reference,
            reason: _string(map, EcrResultKeys.responseMessage),
            raw: _string(map, EcrResultKeys.raw),
          );
        }
        return EcrReceiptReady(
          merchantReferenceId: reference,
          url: url,
          raw: _string(map, EcrResultKeys.raw),
        );
      case EcrOutcomes.unavailable:
        return EcrReceiptUnavailable(
          merchantReferenceId: reference,
          reason: _string(map, EcrResultKeys.responseMessage),
          raw: _string(map, EcrResultKeys.raw),
        );
      case EcrOutcomes.failed:
        return EcrReceiptFailed(
          merchantReferenceId: reference,
          failure: failure(map[EcrResultKeys.failure]),
        );
      case final String unknown:
        return EcrReceiptFailed(
          merchantReferenceId: reference,
          failure: EcrMalformed(_unknownOutcome(unknown, 'a receipt')),
        );
    }
  }

  /// Reads the `recovered` sub-map of a failed result.
  ///
  /// Absent is the normal case — nothing was asked, either because the host was
  /// configured not to or because there was nothing to ask about — and reads as
  /// null rather than as a failed inquiry. Saying "the lookup failed" where no
  /// lookup was made would have a till report a second problem it does not have.
  static EcrInquiry? _recovered(Object? payload, String operationId) {
    if (payload == null) return null;
    return inquiry(payload, operationId: operationId);
  }

  /// Reads a `failure` sub-map.
  ///
  /// An unrecognised kind becomes [EcrMalformed] rather than a guess. A future
  /// native version that adds a failure this one has not heard of will be
  /// reported as "outcome unknown", which is the safe reading.
  static EcrFailure failure(Object? payload) {
    final Map<Object?, Object?>? map = _asMap(payload);
    if (map == null) {
      return EcrMalformed(_notAMap(payload, 'a failure'));
    }

    final String message = _string(map, EcrFailureKeys.message);
    return switch (_string(map, EcrFailureKeys.kind)) {
      EcrFailureKinds.unreachable => EcrUnreachable(message),
      EcrFailureKinds.timeout => EcrTimeout(message),
      EcrFailureKinds.malformed => EcrMalformed(message),
      EcrFailureKinds.connectionLost => EcrConnectionLost(message),
      EcrFailureKinds.unauthenticated => EcrUnauthenticated(message),
      EcrFailureKinds.cancelled =>
        message.isEmpty ? const EcrCancelled() : EcrCancelled(message),
      EcrFailureKinds.unsupported => EcrUnsupported(message),
      final String unknown => EcrMalformed(
          'The host reported a failure this version does not know '
          '("$unknown"): ${message.isEmpty ? 'no message given' : message}',
        ),
    };
  }

  /// Reads a `transaction` sub-map.
  ///
  /// Every field falls back to empty or `false`, which is what the native SDKs
  /// do with the backend's JSON nulls.
  static EcrTransaction transaction(Map<Object?, Object?> map) {
    return EcrTransaction(
      transactionId: _string(map, EcrTransactionKeys.transactionId),
      stan: _string(map, EcrTransactionKeys.stan),
      type: _string(map, EcrTransactionKeys.type),
      status: _string(map, EcrTransactionKeys.status),
      amount: _string(map, EcrTransactionKeys.amount),
      totalAmount: _string(map, EcrTransactionKeys.totalAmount),
      currency: _string(map, EcrTransactionKeys.currency),
      transactionTime: _string(map, EcrTransactionKeys.transactionTime),
      maskedPan: _string(map, EcrTransactionKeys.maskedPan),
      cardHolderName: _string(map, EcrTransactionKeys.cardHolderName),
      rrn: _string(map, EcrTransactionKeys.rrn),
      authCode: _string(map, EcrTransactionKeys.authCode),
      batchId: _string(map, EcrTransactionKeys.batchId),
      terminalId: _string(map, EcrTransactionKeys.terminalId),
      isRefunded: _bool(map, EcrTransactionKeys.isRefunded),
      canVoid: _bool(map, EcrTransactionKeys.canVoid),
      canRefund: _bool(map, EcrTransactionKeys.canRefund),
    );
  }

  static Map<Object?, Object?>? _asMap(Object? value) =>
      value is Map<Object?, Object?> ? value : null;

  /// Reads a string field, whatever it arrived as.
  ///
  /// A null reads as empty rather than as the text "null" — the same rule the
  /// Kotlin SDK's `JsonObject.string` applies. A number arrives as a number on
  /// one platform's codec and a string on the other's for identifiers such as
  /// `terminalId`, so both are accepted and normalised to text.
  static String _string(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    return switch (value) {
      null => '',
      final String text => text,
      _ => value.toString(),
    };
  }

  /// Reads a boolean field.
  ///
  /// Accepts the text forms too: the backend sends `"true"` for some flags and
  /// a real boolean for others, and neither platform's codec normalises that.
  static bool _bool(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    return switch (value) {
      final bool flag => flag,
      'true' => true,
      _ => false,
    };
  }

  static EcrFailed _unreadable(Object? payload, String what) => EcrFailed(
        merchantReferenceId: '',
        failure: EcrMalformed(_notAMap(payload, what)),
      );

  static String _notAMap(Object? payload, String what) =>
      'The host answered $what with ${payload == null ? 'nothing' : payload.runtimeType} '
      'where a map was expected';

  static String _unknownOutcome(String outcome, String what) =>
      'The host reported an outcome for $what that this version does not know '
      '("$outcome"). Treating it as an unknown outcome: reconcile before retrying.';
}
