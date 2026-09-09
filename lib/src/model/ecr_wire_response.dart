import 'dart:convert';

/// Unified ECR response envelope from the terminal:
///
/// `{ success, responseCode, message, data, errorList, nonce?, secureHash? }`
///
/// Mirrors `com.amwalpay.ecr.EcrWireResponse` in the Android SDK.
abstract final class EcrWireResponse {
  /// Reads user-facing text from a raw JSON string: `errorList` first, then
  /// wire `message`. Returns [fallback] when [raw] is empty or invalid.
  static String displayMessageFromRaw(String raw, {String fallback = ''}) {
    if (raw.isEmpty) return fallback;
    final _WireEnvelope? envelope = _WireEnvelope.parse(raw);
    if (envelope == null) return fallback;
    final String message = envelope.displayMessage;
    return message.isNotEmpty ? message : fallback;
  }
}

final class _WireEnvelope {
  _WireEnvelope({
    required this.errorList,
    required this.message,
  });

  final List<String> errorList;
  final String message;

  String get displayMessage =>
      errorList.isNotEmpty ? errorList.join('\n') : message;

  static _WireEnvelope? parse(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, dynamic> root = _root(decoded);
      return _WireEnvelope(
        errorList: _errorList(root, decoded),
        message: _wireMessage(root, decoded),
      );
    } on FormatException {
      return null;
    }
  }

  /// Legacy answers nest under `ecrResponse`; flat fields stay at the top.
  static Map<String, dynamic> _root(Map<dynamic, dynamic> json) {
    if (json.containsKey('success') || json.containsKey('data')) {
      return Map<String, dynamic>.from(json);
    }
    final dynamic nested = json['ecrResponse'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    return Map<String, dynamic>.from(json);
  }

  static List<String> _errorList(
    Map<String, dynamic> root,
    Map<dynamic, dynamic> json,
  ) {
    final dynamic raw = root['errorList'] ?? json['errorList'];
    if (raw is! List) return const <String>[];
    return raw
        .map((dynamic entry) => entry?.toString().trim() ?? '')
        .where((String entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  static String _wireMessage(
    Map<String, dynamic> root,
    Map<dynamic, dynamic> json,
  ) {
    final String message = root['message']?.toString().trim() ?? '';
    if (message.isNotEmpty) return message;
    return json['responseMessage']?.toString().trim() ?? '';
  }
}
