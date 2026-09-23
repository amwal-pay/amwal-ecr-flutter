import 'dart:math';

import '../model/ecr_amount.dart';
import '../model/ecr_config.dart';
import '../model/ecr_errors.dart';
import '../model/ecr_transaction_type.dart';
import 'secure_hash.dart';

/// A LAN ECR request as it goes on the wire.
///
/// Mirrors Kotlin `EcrMessage`.
final class EcrMessage {
  /// [merchantReference] is the resolved reference on the wire; [json] is the
  /// full request body including an optional signature.
  const EcrMessage({
    required this.merchantReference,
    required this.json,
  });

  /// Bumped when the message format changes in a way older terminals cannot
  /// read.
  static const int protocolVersion = 1;

  /// Width the terminal stores and looks up receipt numbers by.
  static const int stanDigits = 6;

  /// Longest reference the terminal will carry.
  static const int merchantReferenceMaxLength = 32;

  static final Set<int> _reservedInReference = <int>{
    '&'.codeUnitAt(0),
    '='.codeUnitAt(0),
  };

  /// The reference this request went out with.
  final String merchantReference;

  /// Wire body, scalar values as Dart ints / strings / bools.
  final Map<String, Object?> json;

  /// The nonce this request went out with, empty when unsigned.
  String get nonce => _string(json['nonce']);

  /// Builds a signed or unsigned request for [type].
  static EcrMessage build({
    required EcrTransactionType type,
    required EcrConfig config,
    required String terminalSerial,
    EcrAmount? amount,
    String originalStan = '',
    String originalTerminalId = '',
    String originalDate = '',
    String originalReference = '',
    String merchantReference = '',
    DateTime? now,
  }) {
    final String reference = resolveMerchantReference(merchantReference);
    final Map<String, Object?> body = <String, Object?>{
      'version': protocolVersion,
      'messageType': type.messageType,
      'merchantReference': reference,
      'terminalSerial': terminalSerial,
      'currencyCode': config.currencyCode,
      'transactionDateTime': _timestamp(now ?? DateTime.now()),
      'ecrId': config.ecrId,
    };

    if (type.requiresAmount) {
      body['amount'] = minorUnits(amount, config.minorUnitDigits);
    }
    if (type.requiresOriginalStan && originalStan.trim().isNotEmpty) {
      body['stan'] = paddedStan(originalStan);
    }
    if (type.allowsOtherTerminal && originalTerminalId.trim().isNotEmpty) {
      body['originalTerminalId'] = originalTerminalId.trim();
    }
    if (type.requiresOriginalDate && originalDate.trim().isNotEmpty) {
      body['originalTransactionDate'] = originalDate.trim();
    }
    if (!type.movesMoney && originalReference.trim().isNotEmpty) {
      body['originalMerchantReference'] =
          resolveMerchantReference(originalReference);
    }
    if (config.signsMessages) {
      body['nonce'] = SecureHash.newNonce();
    }

    final Map<String, Object?> json;
    if (config.signsMessages) {
      final String hash = SecureHash.sign(
        SecureHash.compose(body),
        config.secureHashKey,
      );
      json = <String, Object?>{...body, SecureHash.field: hash};
    } else {
      json = body;
    }

    return EcrMessage(merchantReference: reference, json: json);
  }

  /// The reference to put on the message: the caller's own, or one made here.
  static String resolveMerchantReference(String supplied) {
    final String trimmed = supplied.trim();
    if (trimmed.isEmpty) return _newReference();

    if (trimmed.length > merchantReferenceMaxLength) {
      throw EcrArgumentError(
        'A merchant reference is at most $merchantReferenceMaxLength '
        'characters, was ${trimmed.length}',
      );
    }
    if (!_isAllowedReference(trimmed)) {
      throw EcrArgumentError(
        'A merchant reference takes printable ASCII without spaces, '
        "'&' or '=': was \"$trimmed\"",
      );
    }
    return trimmed;
  }

  /// Amount in minor units, zero-padded to 12 digits (ISO 8583 field 4).
  static String minorUnits(EcrAmount? amount, int digits) {
    if (amount == null) return '0' * 12;
    return amount.toMinorUnits(digits).toString().padLeft(12, '0');
  }

  /// The terminal stores receipt numbers padded; an operator types "24".
  static String paddedStan(String stan) {
    final String digits =
        stan.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');
    if (digits.isEmpty) return '';
    return digits.padLeft(stanDigits, '0');
  }

  static bool _isAllowedReference(String value) {
    for (int i = 0; i < value.length; i++) {
      final int code = value.codeUnitAt(i);
      if (code < 0x21 || code > 0x7E) return false;
      if (_reservedInReference.contains(code)) return false;
    }
    return true;
  }

  static String _timestamp(DateTime local) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}'
        '${two(local.month)}'
        '${two(local.day)}'
        '${two(local.hour)}'
        '${two(local.minute)}'
        '${two(local.second)}';
  }

  static String _newReference() {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 12; i++) {
      buffer.write(random.nextInt(16).toRadixString(16).toUpperCase());
    }
    return buffer.toString();
  }

  static String _string(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }
}
