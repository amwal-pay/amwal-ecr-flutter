import '../model/ecr_next_step.dart';
import 'secure_hash.dart';

/// Parsed unified ECR response envelope.
///
/// Mirrors Kotlin `EcrWireResponse` / `EcrResponseEnvelope`.
final class EcrResponseEnvelope {
  /// Fields normalised from the wire payload.
  const EcrResponseEnvelope({
    required this.success,
    required this.responseCode,
    required this.message,
    required this.data,
    required this.errorList,
    required this.nonce,
    required this.secureHash,
    required this.rawJson,
  });

  /// Whether the envelope reports success / approval.
  final bool success;

  /// Backend or terminal response code.
  final String responseCode;

  /// Top-level `message` / legacy `responseMessage`.
  final String message;

  /// Nested `data` object, when present.
  final Map<String, Object?>? data;

  /// Backend error list entries.
  final List<String> errorList;

  /// Echoed nonce, when signing is in use.
  final String nonce;

  /// Response signature, when present.
  final String secureHash;

  /// Original decoded map (for `raw` on results).
  final Map<String, Object?> rawJson;

  /// User-facing text: `errorList` first, then [message].
  String get displayMessage =>
      errorList.isNotEmpty ? errorList.join('\n') : message;

  /// Merchant reference from `data`, including legacy field names.
  String get merchantReference {
    final Map<String, Object?>? payload = data;
    if (payload == null) return '';
    final String reference = wireString(payload['merchantReference']);
    if (reference.isNotEmpty) return reference;
    final String legacyId = wireString(payload['merchantReferenceId']);
    if (legacyId.isNotEmpty) return legacyId;
    return wireString(payload['requestId']);
  }

  /// Parses [json], including legacy flat / nested shapes.
  static EcrResponseEnvelope parse(Map<String, Object?> json) {
    final Map<String, Object?> root = _root(json);
    return EcrResponseEnvelope(
      success: _isSuccess(json, root),
      responseCode: _responseCode(json, root),
      message: _wireMessage(json, root),
      data: _asObject(root['data']),
      errorList: _errorList(json, root),
      nonce: wireString(json['nonce']),
      secureHash: wireString(json[SecureHash.field]),
      rawJson: json,
    );
  }

  static Map<String, Object?> _root(Map<String, Object?> json) {
    if (json.containsKey('success') || json.containsKey('data')) {
      return json;
    }
    final Map<String, Object?>? nested = _asObject(json['ecrResponse']);
    return nested ?? json;
  }

  static bool _isSuccess(
    Map<String, Object?> json,
    Map<String, Object?> root,
  ) {
    final bool? success = _boolOrNull(root['success']);
    if (success != null) return success;
    final bool? approved = _boolOrNull(json['approved']);
    if (approved != null) return approved;
    return _responseCode(json, root) == '00';
  }

  static String _responseCode(
    Map<String, Object?> json,
    Map<String, Object?> root,
  ) {
    final String code = wireString(root['responseCode']);
    if (code.isNotEmpty) return code;
    return wireString(json['responseCode']);
  }

  static String _wireMessage(
    Map<String, Object?> json,
    Map<String, Object?> root,
  ) {
    final String message = wireString(root['message']);
    if (message.isNotEmpty) return message;
    return wireString(json['responseMessage']);
  }

  static List<String> _errorList(
    Map<String, Object?> json,
    Map<String, Object?> root,
  ) {
    final Object? raw = root['errorList'] ?? json['errorList'];
    if (raw is! List) return const <String>[];
    return raw
        .map((Object? entry) => entry?.toString().trim() ?? '')
        .where((String entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, Object?>? _asObject(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map(
        (Object? key, Object? entry) =>
            MapEntry<String, Object?>(key.toString(), entry),
      );
    }
    return null;
  }

  static bool? _boolOrNull(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return null;
  }
}

/// Reads a wire scalar as text; JSON null becomes empty.
String wireString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

/// Reads a wire boolean; accepts `"true"` text forms.
bool wireFlag(Object? value) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  return false;
}

/// Parses [nextStep] from the wire.
EcrNextStep wireNextStep(Object? value) =>
    EcrNextStep.parse(value is String ? value : value?.toString());
