import 'dart:convert';

import '../model/ecr_inquiry.dart';
import '../model/ecr_receipt.dart';
import '../model/ecr_result.dart';
import '../model/ecr_transaction.dart';
import 'ecr_response_envelope.dart';

/// Maps a terminal JSON answer into typed Dart outcomes.
///
/// Mirrors Kotlin `EcrWireReaders` / Swift `EcrResponseReader`.
abstract final class EcrWireReaders {
  /// Reads a sale / void / refund answer.
  static EcrResult toEcrResult(
    Map<String, Object?> json, {
    required String merchantReference,
    required int minorUnitDigits,
  }) {
    final EcrResponseEnvelope envelope = EcrResponseEnvelope.parse(json);
    final Map<String, Object?>? data = envelope.data;
    final String resolvedReference =
        envelope.merchantReference.isEmpty
            ? merchantReference
            : envelope.merchantReference;
    final String raw = jsonEncode(json);

    if (!envelope.success) {
      return EcrDeclined(
        merchantReference: resolvedReference,
        responseCode: envelope.responseCode,
        reason: envelope.displayMessage.isEmpty
            ? 'Declined'
            : envelope.displayMessage,
        nextStep: wireNextStep(json['nextStep']),
        raw: raw,
      );
    }

    final String amountMajor =
        settledAmountMajor(data, minorUnitDigits, root: json);
    final String requestedMajor = () {
      final String fromData = wireString(data?['amount']);
      if (fromData.isNotEmpty) return fromData;
      return majorUnits(wireString(json['requestedAmount']), minorUnitDigits);
    }();

    return EcrApproved(
      merchantReference: resolvedReference,
      amount: amountMajor,
      responseCode: envelope.responseCode,
      rrn: _firstNonEmpty(
        wireString(data?['rrn']),
        wireString(json['rrn']),
      ),
      authCode: _firstNonEmpty(
        wireString(data?['authCode']),
        wireString(json['authCode']),
      ),
      maskedPan: _firstNonEmpty(
        wireString(data?['cardMask']),
        wireString(data?['maskedPan']),
        wireString(json['maskedPan']),
      ),
      partialApproval: wireFlag(data?['isPartialApprove']) ||
          wireFlag(json['partialApproval']),
      requestedAmount: requestedMajor,
      raw: raw,
    );
  }

  /// Reads an inquiry answer.
  static EcrInquiry toInquiry(
    Map<String, Object?> json, {
    required String merchantReference,
    required int minorUnitDigits,
  }) {
    final EcrResponseEnvelope envelope = EcrResponseEnvelope.parse(json);
    final Map<String, Object?>? data = envelope.data;
    final String resolvedReference =
        envelope.merchantReference.isEmpty
            ? merchantReference
            : envelope.merchantReference;
    final String raw = jsonEncode(json);

    if (data == null) {
      return EcrInquiryNotFound(
        merchantReference: resolvedReference,
        reason: envelope.displayMessage.isEmpty
            ? 'Transaction not found'
            : envelope.displayMessage,
        raw: raw,
      );
    }

    return EcrInquiryFound(
      merchantReference: resolvedReference,
      transaction: EcrTransaction(
        transactionId: wireString(data['transactionId']),
        stan: _firstNonEmpty(
          wireString(data['stan']),
          wireString(data['systemTraceNr']),
        ),
        type: _firstNonEmpty(
          wireString(data['transactionTypeDisplayName']),
          wireString(data['transactionType']),
        ),
        status: () {
          final String status = wireString(data['status']);
          if (status.isNotEmpty) return status;
          return envelope.success ? 'Approved' : 'Declined';
        }(),
        partialApproval: wireFlag(data['isPartialApprove']),
        amount: () {
          final String amount = wireString(data['amount']);
          if (amount.isNotEmpty) return amount;
          return settledAmountMajor(data, minorUnitDigits, root: json);
        }(),
        authorizedAmount: _firstNonEmpty(
          wireString(data['authorizeAmount']),
          wireString(data['amount']),
        ),
        totalAmount: wireString(data['totalAmount']),
        currency: _firstNonEmpty(
          wireString(data['currency']),
          wireString(data['currencyId']),
        ),
        transactionTime: wireString(data['transactionTime']),
        maskedPan: _firstNonEmpty(
          wireString(data['cardMask']),
          wireString(data['cardNumber']),
        ),
        cardHolderName: wireString(data['cardHolderName']),
        rrn: wireString(data['rrn']),
        authCode: wireString(data['authCode']),
        batchId: wireString(data['batchId']),
        terminalId: wireString(data['terminalId']),
        isRefunded: wireFlag(data['isRefunded']),
        canVoid: wireFlag(data['canVoid']),
        canRefund: wireFlag(data['canRefund']),
      ),
      raw: raw,
    );
  }

  /// Reads a receipt answer.
  static EcrReceipt toReceipt(
    Map<String, Object?> json, {
    required String merchantReference,
  }) {
    final EcrResponseEnvelope envelope = EcrResponseEnvelope.parse(json);
    final String resolvedReference =
        envelope.merchantReference.isEmpty
            ? merchantReference
            : envelope.merchantReference;
    final String url = wireString(envelope.data?['receiptUrl']);
    final String raw = jsonEncode(json);

    if (url.isEmpty) {
      return EcrReceiptUnavailable(
        merchantReference: resolvedReference,
        reason: envelope.displayMessage.isEmpty
            ? 'The receipt could not be generated'
            : envelope.displayMessage,
        raw: raw,
      );
    }

    return EcrReceiptReady(
      merchantReference: resolvedReference,
      url: url,
      raw: raw,
    );
  }

  /// Settled amount in major units — prefer `authorizeAmount` when > 0.
  static String settledAmountMajor(
    Map<String, Object?>? data,
    int minorUnitDigits, {
    required Map<String, Object?> root,
  }) {
    if (data != null) {
      final String authorized = wireString(data['authorizeAmount']);
      final double? authorizedValue = double.tryParse(authorized);
      if (authorizedValue != null && authorizedValue > 0) {
        return authorized;
      }
      final String amount = wireString(data['amount']);
      if (amount.isNotEmpty) return amount;
    }
    return majorUnits(wireString(root['amount']), minorUnitDigits);
  }

  /// Converts padded minor units to a major-unit decimal string.
  static String majorUnits(String minorUnits, int digits) {
    if (minorUnits.isEmpty) return '';
    final BigInt? value = BigInt.tryParse(minorUnits);
    if (value == null) return minorUnits;
    if (digits <= 0) return value.toString();
    final bool negative = value.isNegative;
    final BigInt abs = value.abs();
    final String padded = abs.toString().padLeft(digits + 1, '0');
    final int split = padded.length - digits;
    final String text =
        '${padded.substring(0, split)}.${padded.substring(split)}';
    return negative ? '-$text' : text;
  }

  static String _firstNonEmpty(String a, [String b = '', String c = '']) {
    if (a.isNotEmpty) return a;
    if (b.isNotEmpty) return b;
    return c;
  }
}
