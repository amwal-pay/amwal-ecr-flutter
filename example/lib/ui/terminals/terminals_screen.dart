import 'package:flutter/material.dart';

import '../../data/ecr_simulator_settings.dart';
import '../../data/terminal.dart';
import '../../data/terminal_repository.dart';
import '../components/environment_selector.dart';
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

  Future<void> _edit([Terminal? terminal]) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => TerminalEditScreen(
          repository: widget.repository,
          original: terminal,
        ),
      ),
    );
    if (saved ?? false) await _reload();
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
                      (Terminal terminal) => Card(
                        child: ListTile(
                          key: Key('terminal-${terminal.serialNumber}'),
                          title: Text(terminal.name),
                          subtitle: Text(
                            '${terminal.serialNumber}\n'
                            '${terminal.mode.label} · ${terminal.connectionSummary()}',
                          ),
                          isThreeLine: true,
                          onTap: () => _edit(terminal),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove',
                            onPressed: () => _delete(terminal),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
