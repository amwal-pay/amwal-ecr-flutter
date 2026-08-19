/// How the till reaches the terminal.
///
/// Mirrors the `ecrMode` a terminal's TMS profile carries. Only the two IP
/// transports have a listener on the other end: a terminal in ECR mode opens
/// its socket for [ethernet] and [wifi] and leaves the port closed for
/// [bluetooth] and [webService], which are driven by other machinery entirely.
///
/// Naming an unsupported transport is not an error at construction — a till
/// reads the mode from a profile it does not control. It becomes a typed
/// failure at the moment an operation is attempted, so the caller handles it
/// alongside every other reason a transaction did not happen.
enum EcrTransport {
  /// `ecrMode` 1. Wired IP; the SDK connects over TCP.
  ethernet(wireValue: 1, isIpTransport: true),

  /// `ecrMode` 2. Wireless IP; the SDK connects over TCP.
  wifi(wireValue: 2, isIpTransport: true),

  /// `ecrMode` 3. Not carried over IP, so this SDK cannot drive it.
  bluetooth(wireValue: 3, isIpTransport: false),

  /// `ecrMode` 4. The terminal is driven from the payment host, not from the
  /// local network, so this SDK cannot drive it either.
  webService(wireValue: 4, isIpTransport: false);

  const EcrTransport({required this.wireValue, required this.isIpTransport});

  /// The `ecrMode` integer this corresponds to in a TMS profile.
  final int wireValue;

  /// Whether the terminal listens on a socket for this transport, and so
  /// whether this SDK can drive it.
  final bool isIpTransport;

  /// The transport for a TMS `ecrMode`, or `null` when the profile carries a
  /// value this version does not know.
  static EcrTransport? fromWireValue(int value) {
    for (final EcrTransport transport in EcrTransport.values) {
      if (transport.wireValue == value) return transport;
    }
    return null;
  }

  /// The name used on the platform channel.
  String get channelName => name;

  /// The transport named on the channel, or `null` when unrecognised.
  static EcrTransport? fromChannelName(String name) {
    for (final EcrTransport transport in EcrTransport.values) {
      if (transport.channelName == name) return transport;
    }
    return null;
  }
}
