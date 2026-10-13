import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/material.dart';

/// Shows a PRINT answer so the operator can read [EcrPrintOutcome.message].
///
/// Status and message stay on separate lines — never merged into one phrase.
/// Mirrors ECR-simulator `showPrintOutcomeDialog`.
Future<void> showPrintOutcomeDialog(
  BuildContext context,
  EcrPrintOutcome outcome,
) {
  final String body = outcome.message.isEmpty
      ? outcome.status.wire
      : '${outcome.status.wire}\n\n${outcome.message}';
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      key: const Key('printOutcomeDialog'),
      title: const Text('Print receipt'),
      content: Text(body),
      actions: <Widget>[
        TextButton(
          key: const Key('printOutcomeClose'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
