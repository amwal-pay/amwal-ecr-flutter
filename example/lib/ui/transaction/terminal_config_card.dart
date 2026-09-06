import 'package:flutter/material.dart';

import 'selected_terminal_config.dart';

class TerminalConfigCard extends StatelessWidget {
  const TerminalConfigCard({super.key, required this.config});

  final SelectedTerminalConfig config;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      color: config.isReady
          ? colors.surfaceContainerHighest
          : colors.errorContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Active terminal configuration',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _Line(label: 'ECR mode', value: config.mode.label),
            _Line(
              label: 'Transport',
              value: config.usesWebService
                  ? 'Web Service'
                  : config.usesUsbCable
                      ? 'USB cable'
                      : config.usesLan
                          ? 'Wi‑Fi / LAN'
                          : config.mode.label,
            ),
            _Line(label: 'Connection', value: config.connectionSummary),
            _Line(
              label: config.hashKeyLabel,
              value: config.hashKeyConfigured
                  ? 'Configured (${config.ecrConfig.secureHashKey.length} hex chars)'
                  : 'Not configured',
            ),
            for (final String issue in config.issues)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  issue,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
