/// How an ECR reaches the POS terminal — TMS `ecrMode` values.
///
/// `1` USB cable, `2` Wi‑Fi, `3` Bluetooth, `4` Web Service.
enum EcrMode {
  usbCable(1, 'USB Cable'),
  wifi(2, 'Wi‑Fi'),
  bluetooth(3, 'Bluetooth'),
  webService(4, 'Web Service');

  const EcrMode(this.value, this.label);

  final int value;
  final String label;

  /// Whether the terminal is reached over a socket. Wi‑Fi alone.
  bool get isIpBased => this == EcrMode.wifi;

  /// Whether the till reaches the terminal down a USB cable.
  bool get isUsbCable => this == EcrMode.usbCable;

  bool get isSupportedInSimulator =>
      isIpBased || isUsbCable || this == EcrMode.webService;

  static const EcrMode defaultMode = EcrMode.wifi;

  static EcrMode? fromValue(int value) {
    for (final EcrMode mode in EcrMode.values) {
      if (mode.value == value) return mode;
    }
    return null;
  }
}
