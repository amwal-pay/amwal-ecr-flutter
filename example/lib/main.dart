import 'package:flutter/material.dart';

import 'data/terminal_repository.dart';
import 'ui/terminals/terminals_screen.dart';
import 'ui/transaction/transaction_screen.dart';

void main() => runApp(ExampleTillApp(repository: TerminalRepository()));

/// A till driving an Amwal POS terminal over ECR.
///
/// A direct port of the Android example in `app/`: the same two screens, the
/// same settings, the same order of checks, the same dialogs. Where the two
/// apps differ, the Android one is right and this is a bug.
///
/// It is deliberately not a showcase of everything `amwal_ecr` can do. The
/// package offers cancellation, transport selection and a standalone
/// reachability probe; the Android example offers none of those, so neither
/// does this. A till that can abandon a request mid-flight can leave a
/// transaction running on the terminal, and every request after it is answered
/// with `96 — a transaction is already in progress`.
class ExampleTillApp extends StatelessWidget {
  const ExampleTillApp({super.key, required this.repository});

  final TerminalRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amwal ECR',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        useMaterial3: true,
      ),
      home: Builder(
        builder: (BuildContext context) => TransactionScreen(
          repository: repository,
          onManageTerminals: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  TerminalsScreen(repository: repository),
            ),
          ),
        ),
      ),
    );
  }
}
