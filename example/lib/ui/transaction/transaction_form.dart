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
    this.lookUpByReference = false,
    this.originalReference = '',
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

  /// Look the transaction up by the reference this till named it with, rather
  /// than by the receipt number.
  ///
  /// Offered for an inquiry only, and it is the case that matters most: after a
  /// sale whose answer never arrived there is no receipt number to type,
  /// because that number was in the answer.
  final bool lookUpByReference;
  final String originalReference;

  final FormErrors errors;

  bool get showOtherTerminalSwitch => type.allowsOtherTerminal;
  bool get showOriginalTerminal => type.allowsOtherTerminal && useOtherTerminal;

  /// Only an inquiry may look up by reference — see [lookUpByReference].
  bool get showReferenceSwitch => type == EcrTransactionType.inquiry;

  bool get looksUpByReference => showReferenceSwitch && lookUpByReference;

  /// The receipt number field gives way to the reference field.
  bool get showReceiptNumber => type.requiresOriginalStan && !looksUpByReference;

  /// A reference is unique in its own right, so the date is not needed to
  /// disambiguate it the way it is for a receipt number.
  bool get showOriginalDate =>
      type.requiresOriginalDate && !looksUpByReference;

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
    bool? lookUpByReference,
    String? originalReference,
    FormErrors? errors,
  }) =>
      TransactionFormState(
        type: type ?? this.type,
        amountDigits: amountDigits ?? this.amountDigits,
        receiptNumber: receiptNumber ?? this.receiptNumber,
        originalTerminalId: originalTerminalId ?? this.originalTerminalId,
        originalDate: originalDate ?? this.originalDate,
        useOtherTerminal: useOtherTerminal ?? this.useOtherTerminal,
        lookUpByReference: lookUpByReference ?? this.lookUpByReference,
        originalReference: originalReference ?? this.originalReference,
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
        showReceiptNumber && receiptNumber.trim().isEmpty
            ? 'Enter the receipt number of the transaction to act on'
            : null;

    final String? referenceError =
        looksUpByReference && originalReference.trim().isEmpty
            ? 'Enter the reference the transaction was sent with'
            : null;

    final String? terminalError =
        showOriginalTerminal && originalTerminalId.trim().isEmpty
            ? 'Enter the terminal the original was taken on'
            : null;

    final FormErrors validationErrors = FormErrors(
      amount: amountError,
      receiptNumber: receiptError,
      originalTerminalId: terminalError,
      originalReference: referenceError,
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
        receiptNumber: looksUpByReference ? '' : receiptNumber,
        originalTerminalId: showOriginalTerminal ? originalTerminalId : '',
        transactionDate: showOriginalDate ? originalDateOnWire : '',
        originalReference:
            looksUpByReference ? originalReference.trim() : '',
      ),
    );
  }
}

/// Set when a field cannot be sent as it stands.
class FormErrors {
  const FormErrors({
    this.amount,
    this.receiptNumber,
    this.originalTerminalId,
    this.originalReference,
  });

  final String? amount;
  final String? receiptNumber;
  final String? originalTerminalId;
  final String? originalReference;

  bool get any =>
      amount != null ||
      receiptNumber != null ||
      originalTerminalId != null ||
      originalReference != null;
}
