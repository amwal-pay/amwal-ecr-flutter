import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Message authentication for the LAN / Wi‑Fi ECR link.
///
/// Sorted `key=value&…` then HMAC-SHA256 under a hex-decoded key, as uppercase
/// hex — mirrors Kotlin `SecureHash` and Swift `SecureHash`.
abstract final class SecureHash {
  /// Field carrying the signature. Never part of what is signed.
  static const String field = 'secureHash';

  /// Log label for the Wi‑Fi/LAN signing key (distinct from Web Service).
  static const String keyLabel = 'Wi-Fi/LAN secure hash key';

  static const int _nonceBytes = 16;

  /// The exact bytes both sides agree to sign.
  ///
  /// Rules:
  ///  1. Take every top-level entry whose value is a string, number or boolean.
  ///  2. Drop nulls, nested objects and arrays.
  ///  3. Drop [field] itself.
  ///  4. Sort what remains by key.
  ///  5. Join as `key=value`, separated by `&`.
  static String compose(Map<String, Object?> json) {
    final List<MapEntry<String, String>> scalars =
        <MapEntry<String, String>>[];
    for (final MapEntry<String, Object?> entry in json.entries) {
      if (entry.key == field) continue;
      final String? text = _scalar(entry.value);
      if (text == null) continue;
      scalars.add(MapEntry<String, String>(entry.key, text));
    }
    scalars.sort(
      (MapEntry<String, String> a, MapEntry<String, String> b) =>
          a.key.compareTo(b.key),
    );
    return scalars
        .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
        .join('&');
  }

  /// HMAC-SHA256 of [message] under hex-decoded [key], as uppercase hex.
  ///
  /// Throws [FormatException] when [key] is not even-length hex.
  static String sign(String message, String key) {
    final Hmac mac = Hmac(sha256, _decodeKey(key));
    final Digest digest = mac.convert(utf8.encode(message));
    return _toHexUpper(digest.bytes);
  }

  /// Whether [json] carries a signature that matches [key].
  static bool verify(Map<String, Object?> json, String key) {
    final String presented = _string(json[field]);
    if (presented.isEmpty) return false;
    try {
      final String expected = sign(compose(json), key);
      return _constantTimeEquals(presented, expected);
    } on FormatException {
      return false;
    }
  }

  /// A fresh 128-bit nonce, as uppercase hex.
  static String newNonce([Random? random]) {
    final Random source = random ?? Random.secure();
    final Uint8List bytes = Uint8List(_nonceBytes);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = source.nextInt(256);
    }
    return _toHexUpper(bytes);
  }

  static String? _scalar(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is bool) return value ? 'true' : 'false';
    if (value is int) return value.toString();
    if (value is num) {
      // Match JsonPrimitive.content — no scientific notation for protocol ints.
      if (value is double && value == value.roundToDouble()) {
        return value.toInt().toString();
      }
      return value.toString();
    }
    // Maps, lists and anything else are left out of the signing string.
    return null;
  }

  static List<int> _decodeKey(String key) {
    if (key.length < 2 || key.length.isOdd || !_isHex(key)) {
      throw const FormatException(
        'The ECR secret must be an even-length hex string',
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

  static bool _constantTimeEquals(String a, String b) {
    final List<int> left = utf8.encode(a.toUpperCase());
    final List<int> right = utf8.encode(b.toUpperCase());
    if (left.length != right.length) return false;
    int difference = 0;
    for (int i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }

  static String _string(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }
}
