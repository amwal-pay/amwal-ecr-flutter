import 'package:amwal_ecr/amwal_ecr.dart';

import '../amount_limits.dart';
import 'transaction_state.dart';

/// What the operator has entered, and what is wrong with it.
///
/// Which fields apply is decided by [EcrTransactionType], so showing a field
/// and requiring it cannot disagree. Validation answers only "is this complete
/// enough to send" — whether the terminal will accept it needs the payment
/// backend, and only the terminal can ask.
///
/// Mirrors `TransactionForm.kt`.
class TransactionFormState {
  TransactionFormState({
    this.type = EcrTransactionType.sale,
    this.amountDigits = '',
    this.receiptNumber = '',
    this.originalTerminalId = '',
    DateTime? originalDate,
    this.useOtherTerminal = false,
    this.errors = const FormErrors(),
  }) : originalDate = originalDate ?? DateTime.now();

  final EcrTransactionType type;

  /// Raw keyed digits; the amount field renders them as 0.000.
  final String amountDigits;

  final String receiptNumber;
  final String originalTerminalId;

  /// Date of the original transaction, defaulting to today.
  final DateTime originalDate;

  final bool useOtherTerminal;
  final FormErrors errors;

  bool get showOtherTerminalSwitch => type.allowsOtherTerminal;
  bool get showOriginalTerminal => type.allowsOtherTerminal && useOtherTerminal;

  /// The date in the format the terminal looks originals up by.
  String get originalDateOnWire =>
      '${originalDate.year.toString().padLeft(4, '0')}'
      '${originalDate.month.toString().padLeft(2, '0')}'
      '${originalDate.day.toString().padLeft(2, '0')}';

  String get originalDateLabel =>
      '${originalDate.day.toString().padLeft(2, '0')} '
      '${_months[originalDate.month - 1]} ${originalDate.year}';

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  TransactionFormState copyWith({
    EcrTransactionType? type,
    String? amountDigits,
    String? receiptNumber,
    String? originalTerminalId,
    DateTime? originalDate,
    bool? useOtherTerminal,
    FormErrors? errors,
  }) =>
      TransactionFormState(
        type: type ?? this.type,
        amountDigits: amountDigits ?? this.amountDigits,
        receiptNumber: receiptNumber ?? this.receiptNumber,
        originalTerminalId: originalTerminalId ?? this.originalTerminalId,
        originalDate: originalDate ?? this.originalDate,
        useOtherTerminal: useOtherTerminal ?? this.useOtherTerminal,
        errors: errors ?? this.errors,
      );

  /// Validates and returns what to send, or the same state carrying the reasons
  /// it cannot be sent.
  (TransactionFormState, TransactionRequest?) validated(String terminalSerial) {
    final EcrAmount amount = AmountLimits.amountOf(amountDigits);

    final String? amountError = switch (null) {
      _ when !type.requiresAmount => null,
      _ when amount.isZero => 'Required field',
      _ when amount.compareTo(AmountLimits.min) < 0 =>
        'minimum amount allowed is ${AmountLimits.min}',
      _ when amount.compareTo(AmountLimits.max) > 0 =>
        'maximum amount allowed is ${AmountLimits.max}',
      _ => null,
    };

    final String? receiptError =
        type.requiresOriginalStan && receiptNumber.trim().isEmpty
            ? 'Enter the receipt number of the transaction to act on'
            : null;

    final String? terminalError =
        showOriginalTerminal && originalTerminalId.trim().isEmpty
            ? 'Enter the terminal the original was taken on'
            : null;

    final FormErrors validationErrors = FormErrors(
      amount: amountError,
      receiptNumber: receiptError,
      originalTerminalId: terminalError,
    );
    if (validationErrors.any) {
      return (copyWith(errors: validationErrors), null);
    }

    return (
      copyWith(errors: const FormErrors()),
      TransactionRequest(
        type: type,
        terminalSerial: terminalSerial,
        amount: type.requiresAmount ? amount : null,
        receiptNumber: receiptNumber,
        originalTerminalId: showOriginalTerminal ? originalTerminalId : '',
        transactionDate: type.requiresOriginalDate ? originalDateOnWire : '',
      ),
    );
  }
}

/// Set when a field cannot be sent as it stands.
class FormErrors {
  const FormErrors({this.amount, this.receiptNumber, this.originalTerminalId});

  final String? amount;
  final String? receiptNumber;
  final String? originalTerminalId;

  bool get any =>
      amount != null || receiptNumber != null || originalTerminalId != null;
}
