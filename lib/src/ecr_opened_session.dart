import 'ecr_terminal.dart';
import 'model/ecr_config.dart';
import 'model/ecr_transport.dart';

/// One opened [EcrTerminal] for a chosen transport.
///
/// Mirrors native `EcrOpenedSession` / `EcrSessions.open`: apps open once and
/// reuse the same client for sale, inquiry, and recovery so transport dispatch
/// cannot diverge. On Flutter the method channel already unifies LAN / USB /
/// Web Service behind [EcrTerminal]; this type names that intent.
final class EcrOpenedSession {
  EcrOpenedSession(this.terminal);

  final EcrTerminal terminal;

  bool get usesWebService => terminal.transport == EcrTransport.webService;

  bool get usesLocalTerminal =>
      terminal.transport == EcrTransport.wifi ||
      terminal.transport == EcrTransport.usbCable;

  bool get supportsReceipt => usesLocalTerminal;
}

/// Factory that opens a transport-aware [EcrOpenedSession].
abstract final class EcrSessions {
  /// Builds an [EcrOpenedSession] for [transport] with the given addressing.
  static EcrOpenedSession open({
    required String host,
    String serialNumber = '',
    EcrConfig? config,
    EcrTransport transport = EcrTransport.wifi,
  }) {
    return EcrOpenedSession(
      EcrTerminal(
        host: host,
        serialNumber: serialNumber,
        config: config,
        transport: transport,
      ),
    );
  }
}
