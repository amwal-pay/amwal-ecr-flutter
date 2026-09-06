import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ecr_mode.dart';

/// App-owned signing and Web Service settings.
///
/// Persists secrets locally and exposes [secureHashKeyFor] so the selected
/// terminal's mode picks one value for [EcrConfig.secureHashKey]. The ECR
/// plugin/SDK does not store or choose keys.
class EcrSimulatorSettings {
  static const String _keyEnvironment = 'environment';
  static const String _keyWifiSecureHash = 'wifi_secure_hash_key';
  static const String _keySecureHashLegacy = 'secure_hash_key';
  static const String _keyWebServiceSecureHash = 'web_service_secure_hash_key';

  EcrSimulatorSettings(this._prefsInstance);

  final SharedPreferences _prefsInstance;

  static Future<EcrSimulatorSettings> load() async =>
      EcrSimulatorSettings(await SharedPreferences.getInstance());

  EcrEnvironment get environment =>
      EcrEnvironment.fromWireName(_prefsInstance.getString(_keyEnvironment));

  set environment(EcrEnvironment value) =>
      _prefsInstance.setString(_keyEnvironment, value.wireName);

  String get wifiSecureHashKey =>
      _prefsInstance.getString(_keyWifiSecureHash) ??
      _prefsInstance.getString(_keySecureHashLegacy) ??
      '';

  set wifiSecureHashKey(String value) =>
      _prefsInstance.setString(_keyWifiSecureHash, value.trim());

  String get webServiceSecureHashKey =>
      _prefsInstance.getString(_keyWebServiceSecureHash) ?? '';

  set webServiceSecureHashKey(String value) =>
      _prefsInstance.setString(_keyWebServiceSecureHash, value.trim());

  /// Secret to put on [EcrConfig] for the selected terminal [mode].
  String secureHashKeyFor(EcrMode mode) => switch (mode) {
        EcrMode.webService => webServiceSecureHashKey,
        EcrMode.usbCable ||
        EcrMode.wifi ||
        EcrMode.bluetooth =>
          wifiSecureHashKey,
      };
}
