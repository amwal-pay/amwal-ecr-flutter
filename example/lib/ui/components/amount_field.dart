import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../amount_limits.dart';

/// POS-style amount entry.
///
/// The operator keys digits and the field shows where the decimal point falls,
/// the same way the merchant app's purchase form behaves. There is no decimal
/// key, so there is no way to key two points or to leave the point out.
///
/// Mirrors `AmountField.kt`.
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.digits,
    required this.onDigitsChange,
    required this.enabled,
    required this.label,
    this.errorMessage,
    this.supportingText,
  });

  final String digits;
  final ValueChanged<String> onDigitsChange;
  final bool enabled;
  final String label;
  final String? errorMessage;
  final String? supportingText;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  late final TextEditingController _controller =
      TextEditingController(text: AmountLimits.formatDigits(widget.digits));

  @override
  void didUpdateWidget(AmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String rendered = AmountLimits.formatDigits(widget.digits);
    if (_controller.text != rendered) {
      _controller
        ..text = rendered
        ..selection = TextSelection.collapsed(offset: rendered.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('amount'),
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      onChanged: (String value) {
        // Only the digits matter; the point is drawn, not typed.
        final String digits = value
            .replaceAll(RegExp(r'\D'), '')
            .replaceFirst(RegExp(r'^0+(?=\d)'), '');
        widget.onDigitsChange(
          digits.length > AmountLimits.maxDigits
              ? digits.substring(0, AmountLimits.maxDigits)
              : digits,
        );
      },
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        errorText: widget.errorMessage,
        helperText: widget.supportingText,
      ),
    );
  }
}
