import 'package:amwal_ecr/amwal_ecr.dart';

import '../ui/transaction/selected_terminal_config.dart';
import 'ecr_mode.dart';
import 'ecr_simulator_settings.dart';
import 'terminal.dart';

/// Opens SDK sessions for registered terminals.
///
/// Mirrors `TerminalSessions.kt`. One place, because two screens need it: the
/// transaction screen to send, and the terminals screen to show what each
/// terminal will accept. A second copy of the transport rules is a second
/// chance to build a session the SDK would not have.
abstract final class TerminalSessions {
  /// The plan for [terminal] against the saved environment and signing keys.
  static Future<SelectedTerminalConfig> resolve(Terminal terminal) async {
    final EcrSimulatorSettings settings = await EcrSimulatorSettings.load();
    return SelectedTerminalConfig.resolve(
      terminal: terminal,
      environment: settings.environment,
      secureHashKey: settings.secureHashKeyFor(terminal.mode),
    );
  }

  /// Whether the SDK can ask [terminal] what it will accept.
  ///
  /// Wi‑Fi and USB cable only. Web Service has no sign-on, and app to app has
  /// one that is a full handover — the payment app opens, answers and closes,
  /// for a question nobody asked out loud.
  static bool asksSignOn(Terminal terminal) =>
      terminal.mode == EcrMode.wifi || terminal.mode == EcrMode.usbCable;

  /// Opens the SDK terminal for [terminal] under [active].
  static EcrTerminal open(Terminal terminal, SelectedTerminalConfig active) {
    final EcrTransport transport = switch (terminal.mode) {
      EcrMode.usbCable => EcrTransport.usbCable,
      EcrMode.wifi => EcrTransport.wifi,
      EcrMode.bluetooth => EcrTransport.bluetooth,
      EcrMode.webService => EcrTransport.webService,
      EcrMode.appToApp => EcrTransport.appToApp,
    };

    return EcrSessions.open(
      // The one transport whose "address" is an application id: there is no
      // device to dial, because the terminal is this one.
      host: switch (terminal.mode) {
        EcrMode.wifi => terminal.ipAddress,
        EcrMode.appToApp => EcrPaymentApp.packageName,
        _ => '',
      },
      serialNumber: terminal.serialNumber,
      transport: transport,
      config: active.ecrConfig,
    ).terminal;
  }

  /// Asks a terminal what it is and what it will accept.
  ///
  /// A terminal whose own settings do not add up is answered here rather than
  /// on the wire: there is nothing to ask when there is no valid address or
  /// key, and reporting it as a failed exchange would send somebody to look at
  /// a network when the problem is on this screen.
  static Future<EcrSignOn> signOn(Terminal terminal) async {
    if (terminal.mode == EcrMode.appToApp) {
      return const EcrSignOnUnavailable(
        merchantReference: '',
        reason: 'Sign-on is not used for app to app yet — start a transaction '
            'and the terminal answers with what it permits',
        capabilities: EcrTerminalCapabilities(),
        raw: '',
      );
    }

    final SelectedTerminalConfig active = await resolve(terminal);
    if (!active.isReady) {
      return EcrSignOnUnavailable(
        merchantReference: '',
        reason: active.issues.isEmpty
            ? 'This terminal is not configured'
            : active.issues.join('\n'),
        capabilities: const EcrTerminalCapabilities(),
        raw: '',
      );
    }
    return open(terminal, active).signOn();
  }
}
