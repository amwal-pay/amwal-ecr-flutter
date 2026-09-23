import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'secure_hash.dart';

/// Web Service ECR request signing.
///
/// Same sorted `key=value` compose rules as [SecureHash], but the signature
/// field is [field] (`secureHashValue`) rather than `secureHash`.
abstract final class WebServiceSecureHash {
  /// Field added to signed Web Service request bodies.
  static const String field = 'secureHashValue';

  /// Log label for the Web Service signing key (distinct from Wi‑Fi/LAN).
  static const String keyLabel = 'Web Service secure hash key';

  /// HMAC-SHA256 of [message] under hex-decoded [secret], as uppercase hex.
  ///
  /// Returns an empty string on any error — matches Kotlin `calcHash`.
  static String calcHash(String message, String secret) {
    if (secret.isEmpty) return '';
    try {
      final Hmac mac = Hmac(sha256, _decodeHexKey(secret));
      final Digest digest = mac.convert(utf8.encode(message));
      return _toHexUpper(digest.bytes);
    } catch (_) {
      return '';
    }
  }

  /// @see [calcHash]
  static String sign(String payload, String secretKey) =>
      calcHash(payload, secretKey);

  /// Signs [body] after building the sorted `key=value` string.
  static String signBody(Map<String, Object?> body, String secretKey) =>
      calcHash(compose(_unsigned(body)), secretKey);

  /// Returns [body] with [field] set from [secretKey].
  static Map<String, Object?> withHash(
    Map<String, Object?> body,
    String secretKey,
  ) {
    if (secretKey.isEmpty) return Map<String, Object?>.of(body);
    final Map<String, Object?> unsigned = _unsigned(body);
    final String hash = calcHash(compose(unsigned), secretKey);
    if (hash.isEmpty) {
      throw const FormatException(
        'Web Service secureHashValue could not be computed — check the '
        'secure hash key',
      );
    }
    return <String, Object?>{...unsigned, field: hash};
  }

  /// Sorted `key=value&…` signing string (excludes [field]).
  static String payloadString(Map<String, Object?> body) =>
      compose(_unsigned(body));

  /// Same compose rules as [SecureHash.compose], excluding [field].
  static String compose(Map<String, Object?> json) {
    // Reuse LAN compose after temporarily renaming the WS field away from
    // SecureHash.field — WS excludes secureHashValue, LAN excludes secureHash.
    final Map<String, Object?> forCompose = Map<String, Object?>.of(json)
      ..remove(field);
    // SecureHash.compose already drops SecureHash.field; nothing else to do.
    return SecureHash.compose(forCompose);
  }

  static Map<String, Object?> _unsigned(Map<String, Object?> body) =>
      Map<String, Object?>.of(body)..remove(field);

  static List<int> _decodeHexKey(String key) {
    if (key.length < 2 || key.length.isOdd || !_isHex(key)) {
      throw const FormatException(
        'The Web Service secret must be an even-length hex string',
      );
    }
    final Uint8List bytes = Uint8List(key.length ~/ 2);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(key.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  static bool _isHex(String value) {
    for (int i = 0; i < value.length; i++) {
      final int code = value.codeUnitAt(i);
      final bool digit = code >= 0x30 && code <= 0x39;
      final bool upper = code >= 0x41 && code <= 0x46;
      final bool lower = code >= 0x61 && code <= 0x66;
      if (!digit && !upper && !lower) return false;
    }
    return true;
  }

  static String _toHexUpper(List<int> bytes) {
    final StringBuffer buffer = StringBuffer();
    for (final int byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return buffer.toString();
  }
}
