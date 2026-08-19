import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/terminal.dart';
import '../../data/terminal_repository.dart';

/// Adds a terminal, or edits the one whose serial number was passed in.
///
/// Mirrors `TerminalEditScreen.kt`: the same four fields, the same validation,
/// the same refusal on a duplicate serial number.
class TerminalEditScreen extends StatefulWidget {
  const TerminalEditScreen({
    super.key,
    required this.repository,
    this.original,
  });

  final TerminalRepository repository;

  /// The terminal being edited, or null when adding one.
  final Terminal? original;

  @override
  State<TerminalEditScreen> createState() => _TerminalEditScreenState();
}

class _TerminalEditScreenState extends State<TerminalEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.original?.name ?? '');
  late final TextEditingController _serial =
      TextEditingController(text: widget.original?.serialNumber ?? '');
  late final TextEditingController _ip =
      TextEditingController(text: widget.original?.ipAddress ?? '');
  late final TextEditingController _port = TextEditingController(
    text: (widget.original?.port ?? 0) > 0 ? '${widget.original!.port}' : '',
  );

  _TerminalErrors _errors = const _TerminalErrors();
  String? _saveError;

  @override
  void dispose() {
    _name.dispose();
    _serial.dispose();
    _ip.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saveError = null);

    final _TerminalErrors validated = _validate(
      _name.text,
      _serial.text,
      _ip.text,
      _port.text,
    );
    setState(() => _errors = validated);
    if (validated.any) return;

    final SaveOutcome outcome = await widget.repository.save(
      Terminal(
        serialNumber: _serial.text.trim(),
        name: _name.text.trim(),
        ipAddress: _ip.text.trim(),
        port: int.parse(_port.text.trim()),
      ),
      originalSerial: widget.original?.serialNumber,
    );

    if (!mounted) return;
    switch (outcome) {
      case SaveSucceeded():
        Navigator.of(context).pop(true);
      case SaveRejected(:final String reason):
        setState(() => _saveError = reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.original == null ? 'Add terminal' : 'Terminal'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _Field(
              fieldKey: const Key('terminalName'),
              controller: _name,
              label: 'Terminal name',
              error: _errors.name,
              capitalization: TextCapitalization.words,
            ),
            _Field(
              fieldKey: const Key('serialNumber'),
              controller: _serial,
              label: 'Serial number',
              error: _errors.serial ?? _saveError,
              capitalization: TextCapitalization.characters,
            ),
            _Field(
              fieldKey: const Key('ipAddress'),
              controller: _ip,
              label: 'IP address',
              error: _errors.ip,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              formatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
            ),
            _Field(
              fieldKey: const Key('port'),
              controller: _port,
              label: 'Port',
              error: _errors.port,
              keyboardType: TextInputType.number,
              formatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('saveTerminal'),
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.error,
    this.keyboardType = TextInputType.text,
    this.capitalization = TextCapitalization.none,
    this.formatters,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String? error;
  final TextInputType keyboardType;
  final TextCapitalization capitalization;
  final List<TextInputFormatter>? formatters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        key: fieldKey,
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: capitalization,
        inputFormatters: formatters,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorText: error,
        ),
      ),
    );
  }
}

class _TerminalErrors {
  const _TerminalErrors({this.name, this.serial, this.ip, this.port});

  final String? name;
  final String? serial;
  final String? ip;
  final String? port;

  bool get any => name != null || serial != null || ip != null || port != null;
}

/// Dotted-quad, each octet 0-255.
final RegExp _ipv4 = RegExp(
  r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$',
);

_TerminalErrors _validate(String name, String serial, String ip, String port) {
  final int? portNumber = int.tryParse(port.trim());
  return _TerminalErrors(
    name: name.trim().isEmpty ? 'Enter a terminal name' : null,
    serial: serial.trim().isEmpty ? 'Enter the terminal serial number' : null,
    ip: switch (ip.trim()) {
      '' => 'Enter the terminal IP address',
      final String value when !_ipv4.hasMatch(value) =>
        'Enter a valid IPv4 address, for example 192.168.1.50',
      _ => null,
    },
    port: switch (portNumber) {
      null => 'Enter the communication port',
      final int value when value < 1 || value > 65535 =>
        'Port must be between 1 and 65535',
      _ => null,
    },
  );
}
