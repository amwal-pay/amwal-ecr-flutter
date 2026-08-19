/// Operations a terminal can be asked to run.
///
/// Each type declares what the caller has to supply, so a till's own form can
/// be driven from these flags rather than repeating the rules. Mirrors
/// `EcrTransactionType` in the Android SDK field for field.
///
/// What the terminal will *accept* is a separate question, and only the
/// terminal can answer it: whether the original exists, whether it is still
/// within the void window, whether it may be voided at all.
enum EcrTransactionType {
  /// An ordinary purchase.
  sale(
    messageType: 'SALE',
    displayName: 'Sale',
    requiresAmount: true,
    requiresOriginalStan: false,
    requiresOriginalDate: false,
  ),

  /// Cancels an earlier transaction from the same batch, for its full amount.
  /// No card is presented: the terminal already holds the original's details.
  voidTransaction(
    messageType: 'VOID',
    displayName: 'Void',
    requiresAmount: false,
    requiresOriginalStan: true,
    requiresOriginalDate: false,
  ),

  /// Returns money against an earlier transaction, in full or in part. The
  /// cardholder presents their card to receive it.
  refund(
    messageType: 'REFUND',
    displayName: 'Refund',
    requiresAmount: true,
    requiresOriginalStan: true,
    requiresOriginalDate: true,
  ),

  /// Asks what became of an earlier transaction. Reads only: no card is
  /// presented and no money moves, so it is safe to repeat and is answered
  /// even while the terminal is taking a payment.
  inquiry(
    messageType: 'INQUIRY',
    displayName: 'Inquiry',
    requiresAmount: false,
    requiresOriginalStan: true,
    requiresOriginalDate: true,
  ),

  /// Asks for a transaction's e-receipt. Non-financial and reprintable.
  ///
  /// Absent from [menuOptions] by design — a receipt follows a transaction the
  /// operator already has in front of them, so it belongs on that result
  /// rather than in a list of operations.
  receipt(
    messageType: 'RECEIPT',
    displayName: 'Receipt',
    requiresAmount: false,
    requiresOriginalStan: true,
    requiresOriginalDate: true,
  );

  const EcrTransactionType({
    required this.messageType,
    required this.displayName,
    required this.requiresAmount,
    required this.requiresOriginalStan,
    required this.requiresOriginalDate,
  });

  /// The value carried in the message's `messageType` field.
  final String messageType;

  /// A human-readable name, for a client that wants one.
  final String displayName;

  /// Whether the caller supplies an amount. Operations against an earlier
  /// transaction take the original's amount, which only the terminal knows.
  final bool requiresAmount;

  /// Whether the caller identifies an earlier transaction by its receipt
  /// number (STAN).
  final bool requiresOriginalStan;

  /// Whether the caller supplies the date of the original transaction. A
  /// receipt number is only unique within a terminal's day.
  final bool requiresOriginalDate;

  /// Whether the operation moves money. Reading a record does not.
  bool get movesMoney =>
      this == sale || this == voidTransaction || this == refund;

  /// Whether the caller may name a different terminal to act on — only
  /// meaningful for an operation targeting an earlier transaction.
  bool get allowsOtherTerminal => requiresOriginalStan;

  /// The operations an operator picks from, in the order a till usually offers
  /// them. [receipt] is absent by design — see its own note.
  static const List<EcrTransactionType> menuOptions = <EcrTransactionType>[
    sale,
    voidTransaction,
    refund,
    inquiry,
  ];
}
