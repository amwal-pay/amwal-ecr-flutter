import 'dart:async';

import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/material.dart';

import '../../data/ecr_simulator_settings.dart';
import '../../data/terminal.dart';
import '../../data/terminal_repository.dart';
import '../../data/terminal_sessions.dart';
import '../components/environment_selector.dart';
import '../status/sign_on_status.dart';
import '../status/terminal_sign_on_state.dart';
import 'terminal_edit_screen.dart';

class TerminalsScreen extends StatefulWidget {
  const TerminalsScreen({super.key, required this.repository});

  final TerminalRepository repository;

  @override
  State<TerminalsScreen> createState() => _TerminalsScreenState();
}

class _TerminalsScreenState extends State<TerminalsScreen> {
  List<Terminal> _terminals = const <Terminal>[];
  EcrSimulatorSettings? _settings;

  /// What each registered terminal last said about itself, by serial number.
  ///
  /// Shown on the list because a terminal's mode and the operations it permits
  /// are set by TMS, not here: without asking, this screen can only repeat the
  /// address somebody typed, and an operator has no way to tell a terminal that
  /// will take a sale from one that has been moved to another transport.
  final Map<String, TerminalSignOnState> _signOns =
      <String, TerminalSignOnState>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Terminal> terminals = await widget.repository.observeAll().first;
    final EcrSimulatorSettings settings = await EcrSimulatorSettings.load();
    if (!mounted) return;
    setState(() {
      _terminals = terminals;
      _settings = settings;
    });
  }

  /// Asks one terminal what it will accept.
  ///
  /// Only on request. Nothing here asks by itself: opening this screen to
  /// rename a terminal should not start a round of USB handshakes across every
  /// registered one, and a row that has not been checked says so rather than
  /// claiming anything.
  Future<void> _refreshSignOn(Terminal terminal) async {
    final String serial = terminal.serialNumber;
    setState(() => _signOns[serial] = const TerminalAsking());
    final EcrSignOn answer = await TerminalSessions.signOn(terminal);
    if (!mounted) return;
    setState(() => _signOns[serial] = TerminalSignOnState.of(answer));
  }

  Future<void> _edit([Terminal? terminal]) async {
    final Terminal? saved = await Navigator.of(context).push<Terminal>(
      MaterialPageRoute<Terminal>(
        builder: (BuildContext context) => TerminalEditScreen(
          repository: widget.repository,
          original: terminal,
        ),
      ),
    );
    if (saved == null) return;

    // Ask it straight away, so the operator sees what they have just
    // registered rather than a row that says only what they typed. A terminal
    // that cannot be reached is still saved — registration does not depend on
    // the network — and simply reports that it did not answer.
    final String? old = terminal?.serialNumber;
    if (old != null && old != saved.serialNumber) _signOns.remove(old);
    await _reload();
    if (mounted) unawaited(_refreshSignOn(saved));
  }

  Future<void> _delete(Terminal terminal) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Remove terminal'),
        content: Text('Remove ${terminal.name} (${terminal.serialNumber})?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmDelete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await widget.repository.delete(terminal);
      _signOns.remove(terminal.serialNumber);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final EcrSimulatorSettings? settings = _settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS terminals'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('addTerminal'),
        onPressed: _edit,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: settings == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  EcrSimulatorSettingsPanel(
                    environment: settings.environment,
                    wifiSecureHashKey: settings.wifiSecureHashKey,
                    webServiceSecureHashKey: settings.webServiceSecureHashKey,
                    onEnvironmentSelected: (value) {
                      setState(() => settings.environment = value);
                    },
                    onWifiSecureHashKeyChanged: (value) {
                      setState(() => settings.wifiSecureHashKey = value);
                    },
                    onWebServiceSecureHashKeyChanged: (value) {
                      setState(() => settings.webServiceSecureHashKey = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_terminals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'No terminals yet.\nTap + to register a POS terminal.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._terminals.map(
                      (Terminal terminal) => _TerminalCard(
                        terminal: terminal,
                        signOn: _signOns[terminal.serialNumber],
                        onEdit: () => _edit(terminal),
                        onDelete: () => _delete(terminal),
                        onRefresh: () => _refreshSignOn(terminal),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _TerminalCard extends StatelessWidget {
  const _TerminalCard({
    required this.terminal,
    required this.signOn,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });

  final Terminal terminal;
  final TerminalSignOnState? signOn;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const TextStyle mono = TextStyle(fontFamily: 'monospace');
    final EcrTransport? reported = signOn.reportedTransport;

    return Card(
      key: Key('terminal-${terminal.serialNumber}'),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SignOnDot(signOn: signOn),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      terminal.name,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),

              // The mode the operator chose here, and — once the terminal has
              // answered — the mode it is actually on. They are different
              // facts, and a terminal TMS has moved since it was registered is
              // precisely the case worth seeing at a glance.
              Text(
                terminal.mode.label +
                    (reported == null
                        ? ''
                        : ' · terminal reports ${transportWords(reported)}'),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),

              SignOnSummary(signOn: signOn),
              Text('S/N ${terminal.serialNumber}',
                  style: theme.textTheme.bodySmall?.merge(mono)),
              Text(terminal.connectionSummary(),
                  style: theme.textTheme.bodySmall?.merge(mono)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    key: Key('check-${terminal.serialNumber}'),
                    onPressed: onRefresh,
                    child: const Text('Check'),
                  ),
                  TextButton(onPressed: onEdit, child: const Text('Edit')),
                  TextButton(
                    key: Key('delete-${terminal.serialNumber}'),
                    onPressed: onDelete,
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
