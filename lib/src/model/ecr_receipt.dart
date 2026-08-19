import 'ecr_failure.dart';

/// A transaction's e-receipt.
///
/// The receipt is published by the backend and identified by a URL; the till
/// shows that URL as a QR code and the customer reads the receipt on their own
/// phone. Nothing is printed, so a till with no printer can still hand one
/// over.
///
/// Non-financial and reprintable: ask as often as you like, including while the
/// terminal is busy taking a payment.
sealed class EcrReceipt {
  /// Every receipt outcome names the reference it was sent with.
  const EcrReceipt({required this.merchantReferenceId});

  /// The reference this request was sent with, so a caller can match the
  /// answer to what it asked. See `EcrResult.merchantReferenceId`.
  final String merchantReferenceId;
}

/// The receipt is published. Put [url] in a QR code as it stands.
final class EcrReceiptReady extends EcrReceipt {
  /// Carries the published URL.
  const EcrReceiptReady({
    required super.merchantReferenceId,
    required this.url,
    required this.raw,
  });

  /// Never empty — an empty URL is reported as [EcrReceiptUnavailable]
  /// instead, whatever response code came with it. A receipt with no URL is
  /// not a receipt.
  final String url;

  /// The terminal's full answer as JSON text.
  final String raw;

  @override
  String toString() => 'EcrReceiptReady($url)';
}

/// No receipt: the transaction was not found, or the backend would not publish
/// one.
///
/// Harmless — the transaction itself is unaffected, and asking again later is
/// safe.
final class EcrReceiptUnavailable extends EcrReceipt {
  /// Carries whatever the backend said about the refusal.
  const EcrReceiptUnavailable({
    required super.merchantReferenceId,
    required this.reason,
    required this.raw,
  });

  /// The backend's own words about why there is no receipt.
  final String reason;

  /// The terminal's full answer as JSON text.
  final String raw;

  @override
  String toString() => 'EcrReceiptUnavailable($reason)';
}

/// The exchange itself failed. Safe to retry: nothing was changed.
final class EcrReceiptFailed extends EcrReceipt {
  /// Carries why the receipt could not be asked for.
  const EcrReceiptFailed({required super.merchantReferenceId, required this.failure});

  /// Why there was no answer. Safe to retry whatever it says.
  final EcrFailure failure;

  @override
  String toString() => 'EcrReceiptFailed($failure)';
}
