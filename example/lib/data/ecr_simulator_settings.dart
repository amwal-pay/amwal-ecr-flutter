import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ecr_mode.dart';

/// App-wide signing and Web Service settings persisted across launches.
class EcrSimulatorSettings {
  static const String _prefs = 'ecr_simulator_settings';
  static const String _keyEnvironment = 'environment';
  static const String _keyLegacySecureHash = 'secure_hash_key';
  static const String _keyWifiSecureHash = 'wifi_secure_hash_key';
  static const String _keyWebServiceSecureHash = 'web_service_secure_hash_key';

  static const String debugWifiSecureHashKey =
      '881dc200c9833da726e9376c2e32cff7';
  static const String debugWebServiceSecureHashKey =
      'F04359CFB77000AD30DC47136EA1E8B61FD3CAC792B8DDA7CCDC835948260707';

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
      _prefsInstance.getString(_keyLegacySecureHash) ??
      _defaultWifiSecureHashKey();

  set wifiSecureHashKey(String value) =>
      _prefsInstance.setString(_keyWifiSecureHash, value.trim());

  String get webServiceSecureHashKey =>
      _prefsInstance.getString(_keyWebServiceSecureHash) ??
      _defaultWebServiceSecureHashKey();

  set webServiceSecureHashKey(String value) =>
      _prefsInstance.setString(_keyWebServiceSecureHash, value.trim());

  String secureHashKeyFor(EcrMode mode) => switch (mode) {
        EcrMode.webService => webServiceSecureHashKey,
        EcrMode.usbCable ||
        EcrMode.wifi ||
        EcrMode.bluetooth =>
          wifiSecureHashKey,
      };

  static String _defaultWifiSecureHashKey() =>
      kDebugMode ? debugWifiSecureHashKey : '';

  static String _defaultWebServiceSecureHashKey() =>
      kDebugMode ? debugWebServiceSecureHashKey : '';
}
