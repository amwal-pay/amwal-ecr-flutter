import 'package:amwal_ecr/amwal_ecr.dart';

/// What the transaction screen is currently showing.
///
/// Mirrors `TransactionState.kt`.
sealed class TransactionState {
  const TransactionState();

  /// Whether an exchange is under way, so the form stays locked.
  bool get isBusy => this is TransactionChecking || this is TransactionInProgress;
}

/// Nothing running; the screen is waiting for the operator.
final class TransactionIdle extends TransactionState {
  const TransactionIdle();
}

/// Probing the terminal, before anything is sent to it.
final class TransactionChecking extends TransactionState {
  const TransactionChecking();
}

/// Sent, waiting on the cardholder and the terminal.
final class TransactionInProgress extends TransactionState {
  const TransactionInProgress();
}

/// The terminal answered, approved or declined.
///
/// The operation is kept alongside the result: what is worth showing differs by
/// type, and the result itself does not say which was asked for.
final class TransactionCompleted extends TransactionState {
  const TransactionCompleted(this.result, this.type);

  final EcrResult result;
  final EcrTransactionType type;
}

/// An inquiry was answered.
///
/// Kept apart from [TransactionCompleted] because it reports on a transaction
/// rather than one just performed — nothing moved.
final class TransactionInquired extends TransactionState {
  const TransactionInquired({
    required this.inquiry,
    required this.request,
    this.receipt,
    this.fetchingReceipt = false,
  });

  final EcrInquiry inquiry;

  /// Kept so the receipt can be asked for from here: it names the same
  /// transaction, and re-keying it to fetch a receipt would be absurd.
  final TransactionRequest request;

  /// The e-receipt, once fetched. Null until the operator asks for one.
  final EcrReceipt? receipt;

  final bool fetchingReceipt;

  TransactionInquired copyWith({
    EcrReceipt? receipt,
    bool? fetchingReceipt,
  }) =>
      TransactionInquired(
        inquiry: inquiry,
        request: request,
        receipt: receipt ?? this.receipt,
        fetchingReceipt: fetchingReceipt ?? this.fetchingReceipt,
      );
}

/// The exchange itself failed: unreachable, timed out, malformed.
final class TransactionFailed extends TransactionState {
  const TransactionFailed(this.message);

  final String message;
}

/// One operation, as the screen asks for it.
class TransactionRequest {
  const TransactionRequest({
    required this.type,
    required this.terminalSerial,
    required this.amount,
    this.receiptNumber = '',
    this.originalTerminalId = '',
    this.transactionDate = '',
  });

  final EcrTransactionType type;
  final String terminalSerial;

  /// Null for operations that take the original transaction's amount.
  final EcrAmount? amount;

  final String receiptNumber;
  final String originalTerminalId;

  /// `yyyyMMdd`, for operations that look an original up by date.
  final String transactionDate;
}
