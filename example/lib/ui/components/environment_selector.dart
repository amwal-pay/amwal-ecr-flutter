import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wi‑Fi / USB cable and Web Service signing settings.
class EcrSimulatorSettingsPanel extends StatelessWidget {
  const EcrSimulatorSettingsPanel({
    super.key,
    required this.environment,
    required this.wifiSecureHashKey,
    required this.webServiceSecureHashKey,
    required this.onEnvironmentSelected,
    required this.onWifiSecureHashKeyChanged,
    required this.onWebServiceSecureHashKeyChanged,
  });

  final EcrEnvironment environment;
  final String wifiSecureHashKey;
  final String webServiceSecureHashKey;
  final ValueChanged<EcrEnvironment> onEnvironmentSelected;
  final ValueChanged<String> onWifiSecureHashKeyChanged;
  final ValueChanged<String> onWebServiceSecureHashKeyChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SettingsCard(
          title: 'Wi‑Fi / USB cable settings',
          subtitle:
              'Signing key for Wi‑Fi, USB cable, and Bluetooth ECR (LAN protocol).',
          child: _SecureHashKeyField(
            value: wifiSecureHashKey,
            label: 'LAN secure hash key',
            onChanged: onWifiSecureHashKeyChanged,
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          title: 'Web Service settings',
          subtitle: 'Environment and signing key for REST / Hub ECR.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ...EcrEnvironment.values.map(
                (EcrEnvironment option) => RadioListTile<EcrEnvironment>(
                  value: option,
                  groupValue: environment,
                  onChanged: (EcrEnvironment? value) {
                    if (value != null) onEnvironmentSelected(value);
                  },
                  title: Text(option.wireName),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 8),
              _SecureHashKeyField(
                value: webServiceSecureHashKey,
                label: 'Web Service secure hash key',
                onChanged: onWebServiceSecureHashKeyChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SecureHashKeyField extends StatefulWidget {
  const _SecureHashKeyField({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final String value;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  State<_SecureHashKeyField> createState() => _SecureHashKeyFieldState();
}

class _SecureHashKeyFieldState extends State<_SecureHashKeyField> {
  bool _visible = false;
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _SecureHashKeyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool invalid = widget.value.isNotEmpty &&
        !EcrConfig.isValidSecureHashKey(widget.value);

    return TextField(
      controller: _controller,
      obscureText: !_visible,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        errorText: invalid
            ? 'Enter an even-length hex string of at least 16 characters'
            : null,
        suffixIcon: TextButton(
          onPressed: () => setState(() => _visible = !_visible),
          child: Text(_visible ? 'Hide' : 'Show'),
        ),
      ),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
      ],
      onChanged: widget.onChanged,
    );
  }
}
