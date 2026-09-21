/// How an ECR reaches the POS terminal — TMS `ecrMode` values.
///
/// `1` USB cable, `2` Wi‑Fi, `3` Bluetooth, `4` Web Service, `5` app to app.
enum EcrMode {
  usbCable(1, 'USB Cable'),
  wifi(2, 'Wi‑Fi'),
  bluetooth(3, 'Bluetooth'),
  webService(4, 'Web Service'),

  /// The terminal is this device: the transaction is handed to the Amwal
  /// payment app installed beside this one.
  appToApp(5, 'App to app');

  const EcrMode(this.value, this.label);

  final int value;
  final String label;

  /// Whether the terminal is reached over a socket. Wi‑Fi alone.
  bool get isIpBased => this == EcrMode.wifi;

  /// Whether the till reaches the terminal down a USB cable.
  bool get isUsbCable => this == EcrMode.usbCable;

  /// Whether the terminal is the device this app is running on.
  bool get isAppToApp => this == EcrMode.appToApp;

  bool get isSupportedInSimulator =>
      isIpBased || isUsbCable || isAppToApp || this == EcrMode.webService;

  static const EcrMode defaultMode = EcrMode.wifi;

  static EcrMode? fromValue(int value) {
    for (final EcrMode mode in EcrMode.values) {
      if (mode.value == value) return mode;
    }
    return null;
  }
}
