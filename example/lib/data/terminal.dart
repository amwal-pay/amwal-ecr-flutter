import 'ecr_mode.dart';

/// A registered POS terminal.
class Terminal {
  Terminal({
    this.serialNumber = '',
    this.name = '',
    int? ecrMode,
    this.ipAddress = '',
    this.port = 0,
    this.terminalId = '',
    this.merchantId = '',
  }) : ecrMode = ecrMode ?? EcrMode.defaultMode.value;

  factory Terminal.fromJson(Map<String, Object?> json) => Terminal(
        serialNumber: json['serial_number'] as String? ?? '',
        name: json['name'] as String? ?? '',
        ecrMode: json['ecr_mode'] as int? ?? EcrMode.defaultMode.value,
        ipAddress: json['ip_address'] as String? ?? '',
        port: json['port'] as int? ?? 0,
        terminalId: json['terminal_id'] as String? ?? '',
        merchantId: json['merchant_id'] as String? ?? '',
      );

  final String serialNumber;
  final String name;
  final int ecrMode;
  final String ipAddress;
  final int port;
  final String terminalId;
  final String merchantId;

  EcrMode get mode => EcrMode.fromValue(ecrMode) ?? EcrMode.defaultMode;

  Map<String, Object?> toJson() => <String, Object?>{
        'serial_number': serialNumber,
        'name': name,
        'ecr_mode': ecrMode,
        'ip_address': ipAddress,
        'port': port,
        'terminal_id': terminalId,
        'merchant_id': merchantId,
      };

  String connectionSummary() => switch (mode) {
        EcrMode.webService => () {
            final StringBuffer buffer = StringBuffer();
            if (merchantId.isNotEmpty) buffer.write('Merchant $merchantId');
            if (terminalId.isNotEmpty) {
              if (buffer.isNotEmpty) buffer.write(' · ');
              buffer.write('Terminal $terminalId');
            }
            return buffer.isEmpty ? 'Web Service' : buffer.toString();
          }(),
        EcrMode.bluetooth => 'Bluetooth',
        EcrMode.usbCable => 'USB cable',
        EcrMode.wifi => switch ((ipAddress, port)) {
            (final String ip, final int p) when ip.isNotEmpty && p > 0 =>
              '$ip:$p',
            (final String ip, _) when ip.isNotEmpty => ip,
            _ => mode.label,
          },
      };

  @override
  String toString() => '$name ($serialNumber)';

  @override
  bool operator ==(Object other) =>
      other is Terminal && other.serialNumber == serialNumber;

  @override
  int get hashCode => serialNumber.hashCode;
}
