import 'package:flutter/material.dart';

import '../../data/terminal.dart';
import '../../data/terminal_repository.dart';
import 'terminal_edit_screen.dart';

/// Registered POS terminals, with add / edit / delete.
///
/// Mirrors `TerminalsScreen.kt`.
class TerminalsScreen extends StatefulWidget {
  const TerminalsScreen({super.key, required this.repository});

  final TerminalRepository repository;

  @override
  State<TerminalsScreen> createState() => _TerminalsScreenState();
}

class _TerminalsScreenState extends State<TerminalsScreen> {
  List<Terminal> _terminals = const <Terminal>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Terminal> terminals = await widget.repository.observeAll().first;
    if (!mounted) return;
    setState(() => _terminals = terminals);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminals'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('addTerminal'),
        onPressed: _edit,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: _terminals.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No terminals yet.\n'
                    'Add the ones this till drives — the serial number, and the '
                    'address the terminal shows under its card scheme logos.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                itemCount: _terminals.length,
                itemBuilder: (BuildContext context, int index) {
                  final Terminal terminal = _terminals[index];
                  return ListTile(
                    key: Key('terminal-${terminal.serialNumber}'),
                    title: Text(terminal.name),
                    subtitle: Text(
                      '${terminal.serialNumber}\n'
                      '${terminal.ipAddress}:${terminal.port}',
                    ),
                    isThreeLine: true,
                    onTap: () => _edit(terminal),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () => _delete(terminal),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
