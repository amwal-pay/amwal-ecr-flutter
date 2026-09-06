import 'package:amwal_ecr/amwal_ecr.dart';
import '../../data/ecr_secure_hash_labels.dart';

import '../../data/ecr_mode.dart';
import '../../data/terminal.dart';

/// App wrapper around session planning for the selected registered terminal.
class SelectedTerminalConfig {
  const SelectedTerminalConfig({
    required this.terminal,
    required this.issues,
    required this.ecrConfig,
    required this.usesWebService,
    required this.usesLan,
    required this.usesUsbCable,
    required this.hashKeyLabel,
    required this.connectionSummary,
  });

  final Terminal terminal;
  final List<String> issues;
  final EcrConfig ecrConfig;
  final bool usesWebService;
  final bool usesLan;
  final bool usesUsbCable;
  final String hashKeyLabel;
  final String connectionSummary;

  EcrMode get mode => terminal.mode;

  bool get isSupported => mode.isSupportedInSimulator;

  bool get isReady => isSupported && issues.isEmpty;

  bool get hashKeyConfigured => ecrConfig.secureHashKey.isNotEmpty;

  /// Wi‑Fi or USB cable — both use the LAN signing key / protocol.
  bool get usesLocalTerminal => usesLan || usesUsbCable;

  static SelectedTerminalConfig resolve({
    required Terminal terminal,
    required EcrEnvironment environment,
    required String secureHashKey,
  }) {
    final List<String> issues = <String>[];
    if (!terminal.mode.isSupportedInSimulator) {
      issues.add('${terminal.mode.label} is not supported in this simulator');
    }

    final String trimmedKey = secureHashKey.trim();
    final bool validKey =
        trimmedKey.isEmpty || EcrConfig.isValidSecureHashKey(trimmedKey);
    if (trimmedKey.isNotEmpty && !validKey) {
      issues.add(
        'Secure hash key must be an even-length hex string of at least 16 characters',
      );
    }

    final bool usesWebService = terminal.mode == EcrMode.webService;
    final bool usesLan = terminal.mode.isIpBased;
    final bool usesUsbCable = terminal.mode.isUsbCable;

    if (usesLan) {
      if (terminal.ipAddress.trim().isEmpty) {
        issues.add('IP address is required for LAN ECR');
      }
      if (terminal.port < 1 || terminal.port > 65535) {
        issues.add('Port must be between 1 and 65535 (default ${EcrConfig.defaultPort})');
      }
    }

    if (usesWebService) {
      if (terminal.merchantId.trim().isEmpty) {
        issues.add('Merchant ID is required for Web Service');
      }
      if (terminal.terminalId.trim().isEmpty) {
        issues.add('Terminal ID is required for Web Service');
      }
      if (terminal.merchantId.isNotEmpty &&
          int.tryParse(terminal.merchantId) == null) {
        issues.add('Merchant ID must be numeric');
      }
      if (terminal.terminalId.isNotEmpty &&
          int.tryParse(terminal.terminalId) == null) {
        issues.add('Terminal ID must be numeric');
      }
    }

    final String sanitizedKey =
        trimmedKey.isNotEmpty && validKey ? trimmedKey : '';

    if (sanitizedKey.isEmpty) {
      issues.add(
        usesWebService
            ? '${EcrSecureHashLabels.webService} is not configured'
            : '${EcrSecureHashLabels.wifi} is not configured',
      );
    }

    final int port = terminal.port >= 1 && terminal.port <= 65535
        ? terminal.port
        : EcrConfig.defaultPort;

    // Preserve EcrConfig defaults (including autoInquireOnFailure) — same as
    // ecr_sdk app SelectedTerminalConfig.resolve.
    final EcrConfig config = EcrConfig(
      secureHashKey: sanitizedKey,
      merchantId: terminal.merchantId,
      terminalId: terminal.terminalId,
      environment: environment,
      port: port,
    );

    final String summary = usesWebService
        ? () {
            final StringBuffer buffer = StringBuffer(environment.wireName);
            if (terminal.merchantId.isNotEmpty) {
              buffer.write(' · merchant ${terminal.merchantId}');
            }
            if (terminal.terminalId.isNotEmpty) {
              buffer.write(' · terminal ${terminal.terminalId}');
            }
            return buffer.toString();
          }()
        : usesUsbCable
            ? 'USB cable'
            : '${terminal.ipAddress}:$port';

    return SelectedTerminalConfig(
      terminal: terminal,
      issues: issues.toSet().toList(),
      ecrConfig: config,
      usesWebService: usesWebService,
      usesLan: usesLan,
      usesUsbCable: usesUsbCable,
      hashKeyLabel: usesWebService
          ? EcrSecureHashLabels.webService
          : EcrSecureHashLabels.wifi,
      connectionSummary: summary,
    );
  }
}
