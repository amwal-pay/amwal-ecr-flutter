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

  /// Whether the terminal is one this till reaches itself.
  ///
  /// True for the payment app on this same device too: nothing about it goes
  /// through the hub, and it is as local as a terminal gets.
  bool get usesLocalTerminal =>
      terminal.transport == EcrTransport.wifi ||
      terminal.transport == EcrTransport.usbCable ||
      terminal.transport == EcrTransport.appToApp;

  /// Whether the till hands transactions to the payment app on this device.
  bool get usesPaymentApp => terminal.transport == EcrTransport.appToApp;

  /// Whether an e-receipt can be fetched.
  ///
  /// No longer the same question as [usesLocalTerminal]: app to app is local
  /// and still cannot fetch one, so it is asked of the transport rather than
  /// inferred from where the terminal is.
  bool get supportsReceipt => terminal.transport.supportsReceipt;
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
