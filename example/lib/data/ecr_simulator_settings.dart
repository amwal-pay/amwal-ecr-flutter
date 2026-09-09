import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ecr_mode.dart';

/// App-owned signing and Web Service settings.
///
/// Secrets live in platform secure storage (Keychain / Keystore-backed).
/// Environment stays in SharedPreferences. Exposes [secureHashKeyFor] so the
/// selected terminal's mode picks one value for [EcrConfig.secureHashKey]. The
/// ECR plugin/SDK does not store or choose keys.
class EcrSimulatorSettings {
  static const String _keyEnvironment = 'environment';
  static const String _keyWifiSecureHash = 'wifi_secure_hash_key';
  static const String _keySecureHashLegacy = 'secure_hash_key';
  static const String _keyWebServiceSecureHash = 'web_service_secure_hash_key';

  EcrSimulatorSettings._({
    required SharedPreferences prefs,
    required FlutterSecureStorage secure,
    required String wifiSecureHashKey,
    required String webServiceSecureHashKey,
  })  : _prefs = prefs,
        _secure = secure,
        _wifiSecureHashKey = wifiSecureHashKey,
        _webServiceSecureHashKey = webServiceSecureHashKey;

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  String _wifiSecureHashKey;
  String _webServiceSecureHashKey;

  static Future<EcrSimulatorSettings> load({
    SharedPreferences? prefs,
    FlutterSecureStorage? secureStorage,
  }) async {
    final SharedPreferences preferences =
        prefs ?? await SharedPreferences.getInstance();
    final FlutterSecureStorage secure = secureStorage ??
        const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

    String wifi = (await secure.read(key: _keyWifiSecureHash)) ?? '';
    String web = (await secure.read(key: _keyWebServiceSecureHash)) ?? '';

    // One-shot migrate secrets out of plaintext SharedPreferences.
    if (wifi.isEmpty) {
      wifi = preferences.getString(_keyWifiSecureHash) ??
          preferences.getString(_keySecureHashLegacy) ??
          '';
      if (wifi.isNotEmpty) {
        await secure.write(key: _keyWifiSecureHash, value: wifi);
      }
    }
    if (web.isEmpty) {
      web = preferences.getString(_keyWebServiceSecureHash) ?? '';
      if (web.isNotEmpty) {
        await secure.write(key: _keyWebServiceSecureHash, value: web);
      }
    }
    await preferences.remove(_keyWifiSecureHash);
    await preferences.remove(_keySecureHashLegacy);
    await preferences.remove(_keyWebServiceSecureHash);

    return EcrSimulatorSettings._(
      prefs: preferences,
      secure: secure,
      wifiSecureHashKey: wifi,
      webServiceSecureHashKey: web,
    );
  }

  EcrEnvironment get environment =>
      EcrEnvironment.fromWireName(_prefs.getString(_keyEnvironment));

  set environment(EcrEnvironment value) =>
      _prefs.setString(_keyEnvironment, value.wireName);

  String get wifiSecureHashKey => _wifiSecureHashKey;

  set wifiSecureHashKey(String value) {
    final String trimmed = value.trim();
    _wifiSecureHashKey = trimmed;
    _secure.write(key: _keyWifiSecureHash, value: trimmed);
  }

  String get webServiceSecureHashKey => _webServiceSecureHashKey;

  set webServiceSecureHashKey(String value) {
    final String trimmed = value.trim();
    _webServiceSecureHashKey = trimmed;
    _secure.write(key: _keyWebServiceSecureHash, value: trimmed);
  }

  /// Secret to put on [EcrConfig] for the selected terminal [mode].
  String secureHashKeyFor(EcrMode mode) => switch (mode) {
        EcrMode.webService => webServiceSecureHashKey,
        EcrMode.usbCable ||
        EcrMode.wifi ||
        EcrMode.bluetooth =>
          wifiSecureHashKey,
      };
}
