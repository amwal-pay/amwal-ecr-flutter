import 'package:amwal_ecr/amwal_ecr.dart';

import 'ecr_mode.dart';
import 'terminal.dart';

/// Compile-time seeds for a live / lab terminal via `--dart-define`.
///
/// Empty by default so a normal debug build stays blank until the integrator
/// fills Settings. Pass values when pointing at a real POS, for example:
///
/// ```bash
/// flutter run -d windows --dart-define=ECR_ENVIRONMENT=SIT \
///   --dart-define=ECR_WIFI_SECURE_HASH_KEY=<hex> \
///   --dart-define=ECR_WS_SECURE_HASH_KEY=<hex> \
///   --dart-define=ECR_LIVE_MODE=wifi \
///   --dart-define=ECR_LIVE_SERIAL=SN123 \
///   --dart-define=ECR_LIVE_IP=192.168.1.50 \
///   --dart-define=ECR_LIVE_PORT=9100
/// ```
///
/// Web Service live seed:
///
/// ```bash
/// --dart-define=ECR_LIVE_MODE=webService \
/// --dart-define=ECR_LIVE_MERCHANT_ID=… \
/// --dart-define=ECR_LIVE_TERMINAL_ID=…
/// ```
///
/// Seeds apply only when the corresponding stored value is empty, so they
/// never overwrite keys or terminals the user already saved.
class LiveEcrConfig {
  const LiveEcrConfig._();

  static const String environmentWire = String.fromEnvironment(
    'ECR_ENVIRONMENT',
  );
  static const String wifiSecureHashKey = String.fromEnvironment(
    'ECR_WIFI_SECURE_HASH_KEY',
  );
  static const String webServiceSecureHashKey = String.fromEnvironment(
    'ECR_WS_SECURE_HASH_KEY',
  );
  static const String terminalName = String.fromEnvironment(
    'ECR_LIVE_TERMINAL_NAME',
    defaultValue: 'Live terminal',
  );
  static const String serialNumber = String.fromEnvironment(
    'ECR_LIVE_SERIAL',
  );
  static const String ipAddress = String.fromEnvironment('ECR_LIVE_IP');
  static const int port = int.fromEnvironment(
    'ECR_LIVE_PORT',
    defaultValue: 9100,
  );
  static const String merchantId = String.fromEnvironment(
    'ECR_LIVE_MERCHANT_ID',
  );
  static const String terminalId = String.fromEnvironment(
    'ECR_LIVE_TERMINAL_ID',
  );
  static const String modeName = String.fromEnvironment(
    'ECR_LIVE_MODE',
    defaultValue: 'wifi',
  );

  static bool get hasSecureHashSeeds =>
      wifiSecureHashKey.trim().isNotEmpty ||
      webServiceSecureHashKey.trim().isNotEmpty;

  static bool get hasEnvironmentSeed => environmentWire.trim().isNotEmpty;

  static bool get hasTerminalSeed => serialNumber.trim().isNotEmpty;

  static EcrEnvironment? get environmentOrNull {
    final String wire = environmentWire.trim();
    if (wire.isEmpty) return null;
    return EcrEnvironment.fromWireName(wire);
  }

  static EcrMode get mode {
    switch (modeName.trim().toLowerCase()) {
      case 'webservice':
      case 'web_service':
      case 'web-service':
        return EcrMode.webService;
      case 'usb':
      case 'usbcable':
      case 'usb_cable':
        return EcrMode.usbCable;
      case 'bluetooth':
        return EcrMode.bluetooth;
      case 'wifi':
      case 'lan':
      default:
        return EcrMode.wifi;
    }
  }

  /// A terminal row when [hasTerminalSeed] is true; otherwise `null`.
  static Terminal? terminalOrNull() {
    if (!hasTerminalSeed) return null;
    final EcrMode resolved = mode;
    return Terminal(
      serialNumber: serialNumber.trim(),
      name: terminalName.trim().isEmpty ? 'Live terminal' : terminalName.trim(),
      ecrMode: resolved.value,
      ipAddress: resolved.isIpBased ? ipAddress.trim() : '',
      port: resolved.isIpBased ? port : 0,
      merchantId: resolved == EcrMode.webService ? merchantId.trim() : '',
      terminalId: resolved == EcrMode.webService ? terminalId.trim() : '',
    );
  }
}
