/// A transaction as the terminal's backend records it.
///
/// Every field is non-nullable and empty rather than absent, matching the
/// Android SDK: the backend sends JSON `null` for fields it has nothing for —
/// `cardHolderName`, `authCode` on a void — and a till that has to null-check
/// seventeen fields to print a receipt is a till that will miss one.
final class EcrTransaction {
  /// Every field is required: the backend sends them all, and a partial
  /// record is a receipt with a gap in it.
  const EcrTransaction({
    required this.transactionId,
    required this.stan,
    required this.type,
    required this.status,
    required this.amount,
    required this.totalAmount,
    required this.currency,
    required this.transactionTime,
    required this.maskedPan,
    required this.cardHolderName,
    required this.rrn,
    required this.authCode,
    required this.batchId,
    required this.terminalId,
    required this.isRefunded,
    required this.canVoid,
    required this.canRefund,
  });

  /// The backend's own identifier, unique across terminals and days.
  final String transactionId;

  /// The receipt number, unique only within a terminal's day.
  final String stan;

  /// `Sale`, `Void`, `Refund` — as the backend names it, not as this SDK does.
  final String type;

  /// What became of it: `Approved`, `Declined`, `Voided`.
  ///
  /// This, not the inquiry succeeding, is whether money moved.
  final String status;

  /// In **major units**, e.g. `'1.234'` — the backend's own record.
  final String amount;

  /// Including tips and fees, where the transaction carried any.
  final String totalAmount;

  /// The currency's alphabetic code as the backend names it, e.g. `'OMR'`.
  final String currency;

  /// As the backend recorded it, e.g. `'2026-08-09T12:41:07'`.
  final String transactionTime;

  /// Masked, never the full number. May be empty.
  final String maskedPan;

  /// Empty where the backend has no name for the card.
  final String cardHolderName;

  /// Retrieval reference number.
  final String rrn;

  /// Empty on a void, which has no authorisation of its own.
  final String authCode;

  /// The settlement batch this transaction belongs to.
  final String batchId;

  /// The terminal the transaction was taken on. A string even though the
  /// backend sends a number, because it is an identifier and not a quantity.
  final String terminalId;

  /// Whether this transaction has already been refunded.
  final bool isRefunded;

  /// Whether the terminal would accept a void for it **now**.
  ///
  /// The void window and the backend's rules have already been applied, so a
  /// till showing a Void button can ask rather than guess.
  final bool canVoid;

  /// Whether the terminal would accept a refund against it.
  final bool canRefund;

  @override
  String toString() => 'EcrTransaction(stan: $stan, type: $type, '
      'status: $status, amount: $amount $currency)';
}
