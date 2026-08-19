/// A registered POS terminal.
///
/// The serial number is the unique identifier: the transaction screen stores
/// only the serial and looks the IP and port up from here, so a terminal that
/// moves to a new IP needs no change on the transaction side.
///
/// Mirrors `Terminal.kt` in the Android example, field for field.
class Terminal {
  const Terminal({
    this.serialNumber = '',
    this.name = '',
    this.ipAddress = '',
    this.port = 0,
  });

  factory Terminal.fromJson(Map<String, Object?> json) => Terminal(
        serialNumber: json['serial_number'] as String? ?? '',
        name: json['name'] as String? ?? '',
        ipAddress: json['ip_address'] as String? ?? '',
        port: json['port'] as int? ?? 0,
      );

  final String serialNumber;
  final String name;
  final String ipAddress;
  final int port;

  Map<String, Object?> toJson() => <String, Object?>{
        'serial_number': serialNumber,
        'name': name,
        'ip_address': ipAddress,
        'port': port,
      };

  /// Label used in the terminal dropdown on the transaction screen.
  @override
  String toString() => '$name ($serialNumber)';

  @override
  bool operator ==(Object other) =>
      other is Terminal && other.serialNumber == serialNumber;

  @override
  int get hashCode => serialNumber.hashCode;
}
