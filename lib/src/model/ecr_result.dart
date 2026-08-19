import 'ecr_failure.dart';
import 'ecr_inquiry.dart';
import 'ecr_next_step.dart';
import 'ecr_response_code.dart';
import 'ecr_transaction.dart';

/// How a transaction ended.
///
/// The three outcomes are deliberately distinct, because they call for
/// different things from a till: [EcrApproved] means money moved,
/// [EcrDeclined] means the terminal answered and refused, and [EcrFailed]
/// means nothing was learned at all — the last of which may still have taken
/// the customer's money, and must never be treated as a refusal.
///
/// ```dart
/// switch (await terminal.sale(EcrAmount.parse('1.234'))) {
///   case EcrApproved(:final String amount, :final String rrn):
///     print('Took $amount, RRN $rrn');
///   case EcrDeclined(:final String reason):
///     print('Refused: $reason');
///   case EcrFailed(:final EcrFailure failure):
///     print('No answer: ${failure.message}');
/// }
/// ```
sealed class EcrResult {
  /// Every outcome names the reference the transaction was sent with.
  const EcrResult({required this.merchantReferenceId});

  /// The reference the transaction was sent with, so a caller can match the
  /// outcome both to what it sent and to its own record of the sale.
  ///
  /// The caller's own reference where one was given, otherwise the one the
  /// native SDK generated — twelve uppercase hex characters. Either way it is
  /// worth storing: it is what names this transaction to the terminal
  /// afterwards, and the only handle a till holds when an answer goes missing.
  ///
  /// Empty only when the request never left this device.
  final String merchantReferenceId;

  /// Whether the financial outcome is unknown.
  ///
  /// `true` for every [EcrFailed] whose failure leaves it open, and for a
  /// decline carrying response code `91`. A till must not retry while this is
  /// `true` — look the transaction up with
  /// `EcrTerminal.inquireByReference([merchantReferenceId])` and act on that.
  bool get outcomeIsUnknown;

  /// What the terminal says to do about this outcome.
  ///
  /// [EcrNextStep.inquireByMerchantReference] on every [EcrFailed] — no answer
  /// arrived, so nothing about it can say the transaction did not happen — and
  /// whatever the terminal stated on a decline. [EcrNextStep.none] on an
  /// approval.
  EcrNextStep get nextStep;
}

/// Money was taken.
final class EcrApproved extends EcrResult {
  /// Carries what the terminal reported about the money it took.
  const EcrApproved({
    required super.merchantReferenceId,
    required this.amount,
    required this.responseCode,
    required this.rrn,
    required this.authCode,
    required this.maskedPan,
    required this.partialApproval,
    required this.requestedAmount,
    required this.raw,
  });

  /// The amount actually taken, in **major units**, e.g. `'1.234'`.
  ///
  /// A string, not a number: it is the terminal's own figure, and reprinting
  /// exactly what was settled matters more than arithmetic on it. Parse it
  /// with `EcrAmount.parse` where you need to compute.
  final String amount;

  /// The backend's code, `'00'` on a plain approval. See [EcrResponseCode].
  final String responseCode;

  /// Retrieval reference number.
  final String rrn;

  /// Authorisation code.
  ///
  /// A void has no authorisation of its own — it reverses one — so the
  /// terminal returns a placeholder there. Leave it off a void's receipt:
  /// printing it reads as an approval that never took place.
  final String authCode;

  /// Masked, never the full number: `'543173xxxx5785'`. May be empty.
  final String maskedPan;

  /// Set when the bank authorised less than was asked for.
  ///
  /// **This is not a refusal.** The difference has to be collected by other
  /// means, and the goods go out only once it has been.
  final bool partialApproval;

  /// What was asked for, when [partialApproval] is set. Empty otherwise.
  final String requestedAmount;

  /// The terminal's full answer as JSON text, for anything not surfaced above.
  ///
  /// Text rather than a parsed tree so that callers are not forced onto this
  /// package's JSON handling, and so the two platforms cannot disagree about
  /// how a tree is shaped.
  final String raw;

  /// Money moved and the terminal said so.
  @override
  bool get outcomeIsUnknown => false;

  /// Nothing further is needed.
  @override
  EcrNextStep get nextStep => EcrNextStep.none;

  @override
  String toString() =>
      'EcrApproved(merchantReferenceId: $merchantReferenceId, amount: $amount, '
      'rrn: $rrn, partialApproval: $partialApproval)';
}

/// The terminal answered and no money was taken.
final class EcrDeclined extends EcrResult {
  /// Carries the terminal's refusal and the words that came with it.
  const EcrDeclined({
    required super.merchantReferenceId,
    required this.responseCode,
    required this.reason,
    required this.raw,
    this.nextStep = EcrNextStep.none,
  });

  /// The backend's code, or one the terminal generated. See [EcrResponseCode].
  final String responseCode;

  /// The backend's own words where it gave any — its error list in preference
  /// to its generic message.
  final String reason;

  /// The terminal's full answer as JSON text.
  final String raw;

  /// What to do about it.
  ///
  /// Usually [EcrNextStep.none] — a decline says plainly that no money moved —
  /// but the terminal can report that it does not actually know, and then this
  /// asks for an inquiry rather than a retry.
  @override
  final EcrNextStep nextStep;

  /// A transaction was already running on the terminal.
  ///
  /// Nothing was attempted, so this one is safe to send again once the
  /// terminal is free.
  bool get isTerminalBusy => responseCode == EcrResponseCode.terminalBusy;

  /// Cancelled at the terminal, by the operator or the cardholder.
  bool get isCancelledAtTerminal =>
      responseCode == EcrResponseCode.cancelledAtTerminal;

  /// The original transaction was not found — a void or refund against a
  /// receipt number the terminal does not have for that day.
  bool get isOriginalNotFound =>
      responseCode == EcrResponseCode.originalNotFound;

  /// The terminal refused the request itself: unsigned, signed with a key it
  /// does not hold, or a clock more than five minutes from its own.
  ///
  /// A configuration fault rather than a payment decision, so it is worth
  /// telling an operator apart from a decline: no card was read and retrying
  /// changes nothing until the key or the clock is put right. [reason] carries
  /// the terminal's own words for which of the three it was.
  bool get isSecurityViolation =>
      responseCode == EcrResponseCode.securityViolation;

  /// Response code `91`: the terminal could not say what happened.
  ///
  /// The one decline that is not a decision. Reconcile rather than retry.
  @override
  bool get outcomeIsUnknown =>
      EcrResponseCode.leavesOutcomeUnknown(responseCode) ||
      nextStep.needsInquiry;

  @override
  String toString() =>
      'EcrDeclined(merchantReferenceId: $merchantReferenceId, '
      'responseCode: $responseCode, reason: $reason)';
}

/// The exchange itself failed, so the outcome is whatever [failure] says.
final class EcrFailed extends EcrResult {
  /// Carries why there was no answer, and whether money may have moved.
  const EcrFailed({
    required super.merchantReferenceId,
    required this.failure,
    this.recovered,
  });

  /// Why there was no answer, and whether money may nonetheless have moved.
  final EcrFailure failure;

  /// What the terminal said when asked afterwards, or null when it was not
  /// asked.
  ///
  /// The native SDK follows a lost exchange with an inquiry by
  /// [merchantReferenceId] — see `EcrConfig.autoInquireOnFailure` — because that
  /// is the only way to learn an outcome whose answer never arrived, and the
  /// thing a till reaches for instead is sending the sale again.
  ///
  /// [EcrInquiryFound] settles it: the transaction exists, and
  /// [EcrTransaction.status] says what became of it. Anything else means it is
  /// still unknown, and money may still have moved.
  final EcrInquiry? recovered;

  /// Whether the follow-up actually found the transaction, so this is no longer
  /// an unknown outcome — only a delivery that failed.
  bool get settled => recovered is EcrInquiryFound;

  /// The transaction the follow-up found, or null when nothing was found.
  ///
  /// The shortest path from "the answer never arrived" to "here is what actually
  /// happened", which is the whole reason the follow-up is made.
  EcrTransaction? get recoveredTransaction =>
      recovered is EcrInquiryFound
          ? (recovered! as EcrInquiryFound).transaction
          : null;

  /// Unknown unless the follow-up found the transaction.
  ///
  /// A [settled] failure is a delivery that failed and an outcome that is known:
  /// the till can book what [recoveredTransaction] says and stop worrying about
  /// a double charge.
  @override
  bool get outcomeIsUnknown => failure.outcomeIsUnknown && !settled;

  /// Always [EcrNextStep.inquireByMerchantReference]: no answer arrived at all,
  /// so nothing here can say the transaction did not happen.
  @override
  EcrNextStep get nextStep => EcrNextStep.inquireByMerchantReference;

  @override
  String toString() =>
      'EcrFailed(merchantReferenceId: $merchantReferenceId, '
      'failure: $failure, settled: $settled)';
}
