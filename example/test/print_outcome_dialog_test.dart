import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr_example/print/print_outcome_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('print outcome dialog shows status and message separately',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showPrintOutcomeDialog(
              context,
              const EcrPrintOutcome(
                status: EcrPrintStatus.successful,
                message: 'Printed on terminal',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('printOutcomeDialog')), findsOneWidget);
    expect(find.text('Print receipt'), findsOneWidget);
    expect(find.text('SUCCESSFUL\n\nPrinted on terminal'), findsOneWidget);

    await tester.tap(find.byKey(const Key('printOutcomeClose')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('printOutcomeDialog')), findsNothing);
  });

  testWidgets('print outcome dialog falls back to status when message is empty',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showPrintOutcomeDialog(
              context,
              EcrPrintOutcome.failed(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('FAILED'), findsOneWidget);
  });
}
