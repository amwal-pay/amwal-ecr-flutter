import 'ecr_failure.dart';

/// What came of asking the terminal to settle its batch.
///
/// Safe to retry in every case. A settlement whose answer went missing has
/// either closed the batch, and a second one finds [EcrSettlementNothingToSettle],
/// or it has not, and the second one does what the first was meant to.
sealed class EcrSettlement {
  /// Every outcome names the reference it was sent with.
  const EcrSettlement({required this.merchantReference});

  /// The reference this request was sent with, so a caller can match the
  /// answer to what it asked. See `EcrResult.merchantReference`.
  final String merchantReference;
}

/// One row of a settlement's totals. [amount] is in major units.
final class EcrSettlementTotal {
  /// A count and what it came to.
  const EcrSettlementTotal({required this.count, required this.amount});

  /// How many transactions of this type the batch held.
  final int count;

  /// What they came to, in major units: `'14.750'`.
  final String amount;

  @override
  bool operator ==(Object other) =>
      other is EcrSettlementTotal &&
      other.count == count &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(count, amount);

  @override
  String toString() => 'EcrSettlementTotal($count, $amount)';
}

/// The batch was closed. The totals are the ones the terminal printed.
///
/// Amounts are in major units, as everywhere else this plugin reports money:
/// `'12.500'`, not `'000000012500'`.
final class EcrSettlementSettled extends EcrSettlement {
  /// Carries the closed batch.
  const EcrSettlementSettled({
    required super.merchantReference,
    required this.batchId,
    required this.currency,
    required this.startTime,
    required this.endTime,
    required this.totalTransactions,
    required this.netAmount,
    required this.totals,
    required this.raw,
  });

  /// The types [totals] is keyed by, in the order a receipt lists them.
  static const List<String> totalTypes = <String>[
    'SALE',
    'REFUND',
    'VOID',
    'PRE_AUTH',
    'CAPTURE',
  ];

  /// The batch that was closed.
  final String batchId;

  /// ISO 4217 alphabetic, e.g. `OMR`.
  final String currency;

  /// When the batch opened, `yyyyMMddHHmmss` terminal time.
  final String startTime;

  /// When it was closed, `yyyyMMddHHmmss` terminal time; empty if not reported.
  final String endTime;

  /// How many transactions the batch held.
  final int totalTransactions;

  /// What the batch came to after refunds and voids, in major units.
  final String netAmount;

  /// Count and amount per type, keyed by every entry of [totalTypes] — zeros
  /// for a type the batch had none of — so a till can print a fixed layout.
  final Map<String, EcrSettlementTotal> totals;

  /// The terminal's full answer as JSON text.
  final String raw;

  @override
  String toString() =>
      'EcrSettlementSettled($batchId, $totalTransactions, $netAmount)';
}

/// The batch held nothing to settle. Not a failure: there is nothing left open.
final class EcrSettlementNothingToSettle extends EcrSettlement {
  /// Carries the terminal's own words.
  const EcrSettlementNothingToSettle({
    required super.merchantReference,
    required this.message,
    required this.raw,
  });

  /// The terminal's own words.
  final String message;

  /// The terminal's full answer as JSON text.
  final String raw;

  @override
  String toString() => 'EcrSettlementNothingToSettle()';
}

/// The terminal answered and the batch is still open.
///
/// [status] says why: `MISMATCH` (the backend counted a different number of
/// transactions — see [uploadedTransactions]), `SESSION_EXPIRED` (someone has
/// to sign the terminal in again) or `FAILED`. A request refused before it
/// started — the terminal busy (`96`), not on its idle screen (`91`), or too
/// old to know settlement (`12`) — has an empty [status].
final class EcrSettlementNotSettled extends EcrSettlement {
  /// Carries why the batch is still open.
  const EcrSettlementNotSettled({
    required super.merchantReference,
    required this.responseCode,
    required this.status,
    required this.reason,
    this.uploadedTransactions,
    required this.raw,
  });

  /// The terminal's response code.
  final String responseCode;

  /// The terminal's `settlementStatus`; empty for a refusal before it started.
  final String status;

  /// The terminal's own words.
  final String reason;

  /// What the terminal uploaded, on a `MISMATCH`.
  final int? uploadedTransactions;

  /// The terminal's full answer as JSON text.
  final String raw;

  @override
  String toString() => 'EcrSettlementNotSettled($responseCode $status $reason)';
}

/// The exchange itself failed. Safe to retry.
final class EcrSettlementFailed extends EcrSettlement {
  /// Carries why the terminal could not be asked.
  const EcrSettlementFailed({
    required super.merchantReference,
    required this.failure,
  });

  /// Why there was no answer.
  final EcrFailure failure;

  @override
  String toString() => 'EcrSettlementFailed($failure)';
}
