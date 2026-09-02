/// How an ECR reaches the POS terminal — TMS `ecrMode` values.
enum EcrMode {
  ethernet(1, 'Ethernet'),
  wifi(2, 'Wi‑Fi'),
  bluetooth(3, 'Bluetooth'),
  webService(4, 'Web Service');

  const EcrMode(this.value, this.label);

  final int value;
  final String label;

  bool get isIpBased => this == EcrMode.ethernet || this == EcrMode.wifi;

  bool get isSupportedInSimulator => isIpBased || this == EcrMode.webService;

  static const EcrMode defaultMode = EcrMode.wifi;

  static EcrMode? fromValue(int value) {
    for (final EcrMode mode in EcrMode.values) {
      if (mode.value == value) return mode;
    }
    return null;
  }
}
