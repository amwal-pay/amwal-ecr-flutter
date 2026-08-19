import 'ecr_failure.dart';
import 'ecr_transaction.dart';

/// The answer to "what became of this transaction".
///
/// Kept apart from `EcrResult` because it reports on a transaction rather than
/// performing one: an inquiry that succeeds says nothing about whether money
/// moved — that is [EcrTransaction.status].
///
/// This is what a till reaches for after a timeout. The outcome is unknown; an
/// inquiry is how to find out, instead of retrying and risking a second charge.
sealed class EcrInquiry {
  /// Every inquiry outcome names the reference it was sent with.
  const EcrInquiry({required this.merchantReferenceId});

  /// The reference this request was sent with, so a caller can match the
  /// answer to what it asked. See `EcrResult.merchantReferenceId`.
  final String merchantReferenceId;
}

/// The transaction was found. What became of it is
/// [EcrTransaction.status] — finding it is not the same as it having been paid.
final class EcrInquiryFound extends EcrInquiry {
  /// Carries the backend's own record of the transaction.
  const EcrInquiryFound({
    required super.merchantReferenceId,
    required this.transaction,
    required this.raw,
  });

  /// The transaction the terminal's backend has on file.
  final EcrTransaction transaction;

  /// The terminal's full answer as JSON text.
  final String raw;

  @override
  String toString() => 'EcrInquiryFound($transaction)';
}

/// No such transaction on that terminal for that day.
///
/// [reason] carries the backend's own words where it gave any — a receipt
/// number from another terminal and one that never existed read alike from the
/// till, and the terminal is the only side that can tell them apart.
final class EcrInquiryNotFound extends EcrInquiry {
  /// Carries whatever the backend said about the lookup.
  const EcrInquiryNotFound({
    required super.merchantReferenceId,
    required this.reason,
    required this.raw,
  });

  /// The backend's own words about why nothing was found.
  final String reason;

  /// The terminal's full answer as JSON text.
  final String raw;

  @override
  String toString() => 'EcrInquiryNotFound($reason)';
}

/// The exchange itself failed, so nothing was learned.
///
/// Unlike a failed sale this is harmless to retry: an inquiry changes nothing.
final class EcrInquiryFailed extends EcrInquiry {
  /// Carries why the lookup could not be made.
  const EcrInquiryFailed({required super.merchantReferenceId, required this.failure});

  /// Why there was no answer. Safe to retry whatever it says.
  final EcrFailure failure;

  @override
  String toString() => 'EcrInquiryFailed($failure)';
}
