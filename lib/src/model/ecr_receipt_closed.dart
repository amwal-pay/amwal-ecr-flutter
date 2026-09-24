import 'ecr_failure.dart';

/// What came of asking the terminal to put its receipt away.
///
/// A receipt waits for the operator, because normally the operator is the
/// person standing at the terminal. Driven by a till they are not — they are
/// at the till — so the receipt sits there until somebody walks over and
/// presses back, and the terminal refuses the next transaction until they do.
///
/// Every outcome here is safe to retry. Nothing moves money, and a terminal
/// that was already idle answers exactly as one that had a receipt to close:
/// the request asks for a state rather than for an action, and that state
/// holds either way.
sealed class EcrReceiptClosed {
  /// Every outcome names the reference it was sent with.
  const EcrReceiptClosed({required this.merchantReference});

  /// The reference this request was sent with, so a caller can match the
  /// answer to what it asked. See `EcrResult.merchantReference`.
  final String merchantReference;
}

/// The terminal is on its idle screen and ready for the next transaction.
final class EcrReceiptClosedIdle extends EcrReceiptClosed {
  /// Carries the terminal's answer.
  const EcrReceiptClosedIdle({
    required super.merchantReference,
    required this.raw,
  });

  /// The terminal's full answer as JSON text.
  final String raw;

  @override
  String toString() => 'EcrReceiptClosedIdle()';
}

/// The terminal answered and refused.
///
/// In practice this is a terminal too old to know the request, which answers
/// `12`. Treat it as "this terminal cannot be asked" rather than as an error
/// worth putting in front of a cashier: the receipt stays up and somebody
/// presses back, exactly as it did before this existed.
final class EcrReceiptClosedRefused extends EcrReceiptClosed {
  /// Carries the terminal's own words.
  const EcrReceiptClosedRefused({
    required super.merchantReference,
    required this.responseCode,
    required this.reason,
    required this.raw,
  });

  /// The terminal's response code. `12` for a terminal that does not know the
  /// request.
  final String responseCode;

  /// The terminal's own words about the refusal.
  final String reason;

  /// The terminal's full answer as JSON text.
  final String raw;

  @override
  String toString() => 'EcrReceiptClosedRefused($responseCode $reason)';
}

/// The exchange itself failed. Safe to retry: nothing was changed.
final class EcrReceiptClosedFailed extends EcrReceiptClosed {
  /// Carries why the terminal could not be asked.
  const EcrReceiptClosedFailed({
    required super.merchantReference,
    required this.failure,
  });

  /// Why there was no answer. Safe to retry whatever it says.
  final EcrFailure failure;

  @override
  String toString() => 'EcrReceiptClosedFailed($failure)';
}
