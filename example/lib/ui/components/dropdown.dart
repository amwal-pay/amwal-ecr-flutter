import 'package:flutter/material.dart';

/// A read-only field that opens a list of choices.
///
/// Mirrors `Dropdown.kt`.
class Dropdown<T> extends StatelessWidget {
  const Dropdown({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    required this.labelOf,
    this.fieldKey,
  });

  final String label;
  final List<T> options;
  final T? selected;
  final bool enabled;
  final ValueChanged<T> onSelected;
  final String Function(T option) labelOf;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: fieldKey,
      initialValue: selected,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<T>>[
        for (final T option in options)
          DropdownMenuItem<T>(value: option, child: Text(labelOf(option))),
      ],
      onChanged: enabled
          ? (T? value) {
              if (value != null) onSelected(value);
            }
          : null,
    );
  }
}
