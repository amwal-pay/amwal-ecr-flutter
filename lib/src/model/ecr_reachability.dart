/// Result of [EcrTerminal.probeReachability].
///
/// Mirrors `EcrReachability` in the Android and iOS SDKs. [error] carries
/// whatever the link reported when the probe failed — connection refused, a
/// timeout, a cable that is not plugged in — so a till can show *why* rather
/// than only that the terminal is not there.
final class EcrReachability {
  /// Creates a probe result. When [endpoint] is omitted, it is derived from
  /// [host] and [port] the same way the native SDKs do.
  const EcrReachability({
    required this.reachable,
    required this.host,
    required this.port,
    this.error,
    String? endpoint,
  }) : endpoint = endpoint ?? (port > 0 ? '$host:$port' : host);

  /// Whether the terminal answered the probe.
  final bool reachable;

  /// Address side of the link. Empty for a cable with no IP.
  final String host;

  /// Listener port, or `0` when the link is not a socket.
  final int port;

  /// Why the probe failed, when it did. Null when [reachable] is true.
  final String? error;

  /// What to show an operator: `host:port` over Wi‑Fi, the cable otherwise.
  final String endpoint;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EcrReachability &&
          reachable == other.reachable &&
          host == other.host &&
          port == other.port &&
          error == other.error &&
          endpoint == other.endpoint;

  @override
  int get hashCode => Object.hash(reachable, host, port, error, endpoint);

  @override
  String toString() =>
      'EcrReachability(reachable: $reachable, endpoint: $endpoint'
      '${error == null ? '' : ', error: $error'})';
}
