import 'package:amwal_ecr/amwal_ecr.dart';

/// What a registered terminal last said about itself, for a screen to show.
///
/// Mirrors `TerminalSignOnState.kt`. Four states rather than three: "nobody
/// has asked yet" and "it was asked and did not answer" look the same on a row
/// and mean opposite things, so an operator has to be able to tell them apart.
sealed class TerminalSignOnState {
  const TerminalSignOnState();

  /// Maps the SDK's answer onto what a screen shows.
  factory TerminalSignOnState.of(EcrSignOn answer) => switch (answer) {
        EcrSignOnAvailable(:final EcrTerminalCapabilities capabilities) =>
          TerminalReady(capabilities),
        EcrSignOnUnavailable(
          :final String reason,
          :final EcrTerminalCapabilities capabilities
        ) =>
          TerminalNotReady(reason: reason, capabilities: capabilities),
        EcrSignOnFailed(:final EcrFailure failure) =>
          TerminalNoAnswer(failure.message),
      };
}

/// The request is out.
final class TerminalAsking extends TerminalSignOnState {
  const TerminalAsking();
}

/// It answered and is in service.
final class TerminalReady extends TerminalSignOnState {
  const TerminalReady(this.capabilities);

  final EcrTerminalCapabilities capabilities;
}

/// It answered and cannot serve a transaction, and said why.
final class TerminalNotReady extends TerminalSignOnState {
  const TerminalNotReady({required this.reason, required this.capabilities});

  final String reason;
  final EcrTerminalCapabilities capabilities;
}

/// Nothing came back. Nothing is claimed about the terminal.
final class TerminalNoAnswer extends TerminalSignOnState {
  const TerminalNoAnswer(this.reason);

  final String reason;
}

/// Reads made through a nullable state, because a row renders before anything
/// has been asked and "not asked yet" is one of the states these answer for.
extension TerminalSignOnStateReads on TerminalSignOnState? {
  /// What the terminal said it will accept, or null when it has not said.
  ///
  /// Everything shown about a terminal is read through here, so the screen has
  /// one answer rather than two that can drift apart.
  EcrTerminalCapabilities? get terminalCapabilities => switch (this) {
        TerminalReady(:final EcrTerminalCapabilities capabilities) =>
          capabilities,
        TerminalNotReady(:final EcrTerminalCapabilities capabilities) =>
          capabilities,
        _ => null,
      };

  /// The transport the terminal reports, or null when it did not say.
  EcrTransport? get reportedTransport => terminalCapabilities?.transport;

  /// The operations the terminal permits, empty when it did not say.
  List<String> get permitted => (terminalCapabilities?.permitted ??
          const <EcrPermittedTransaction>[])
      .map((EcrPermittedTransaction entry) => entry.type.displayName)
      .toList();
}
