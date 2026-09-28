import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/material.dart';

import 'terminal_sign_on_state.dart';

/// How a transport reads on screen: `usbCable` → `usb cable`.
String transportWords(EcrTransport transport) => transport.name
    .replaceAllMapped(RegExp('[A-Z]'), (Match m) => ' ${m[0]!.toLowerCase()}');

/// Green when the terminal will take a transaction, red when it will not.
///
/// Grey while nobody has asked — which is not the same as "no", and must not
/// be shown as one. A red dot on a terminal that has simply not been checked
/// would send an operator to look for a fault that is not there.
class SignOnDot extends StatelessWidget {
  const SignOnDot({super.key, required this.signOn});

  final TerminalSignOnState? signOn;

  @override
  Widget build(BuildContext context) {
    if (signOn is TerminalAsking) {
      return const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color colour = switch (signOn) {
      TerminalReady() => const Color(0xFF2E7D32),
      TerminalNotReady() || TerminalNoAnswer() => scheme.error,
      _ => scheme.outline,
    };

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
    );
  }
}

/// Why a terminal is not ready, and what it will accept when it is.
class SignOnSummary extends StatelessWidget {
  const SignOnSummary({super.key, required this.signOn});

  final TerminalSignOnState? signOn;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? small = theme.textTheme.bodySmall;

    return switch (signOn) {
      null || TerminalAsking() => const SizedBox.shrink(),
      TerminalReady() when signOn.permitted.isEmpty => const SizedBox.shrink(),
      TerminalReady() => Text(
          signOn.permitted.join(' · '),
          key: const Key('signOnPermitted'),
          style: small?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      TerminalNotReady(:final String reason) => Text(
          reason,
          key: const Key('signOnReason'),
          style: small?.copyWith(color: theme.colorScheme.error),
        ),
      // Said plainly, because it is a different fact from a terminal that
      // answered and refused: nothing is known about this one at all.
      TerminalNoAnswer(:final String reason) => Text(
          'No answer — $reason',
          key: const Key('signOnNoAnswer'),
          style: small?.copyWith(color: theme.colorScheme.error),
        ),
    };
  }
}
