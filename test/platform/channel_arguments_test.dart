import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/amwal_ecr_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_host.dart';

/// What actually crosses the channel: the field, its type, whether it may be
/// null, and — the one that costs money when it is wrong — its unit.
void main() {
  late FakeEcrHost host;
  late EcrTerminal terminal;

  setUp(() {
    host = FakeEcrHost();
    terminal = EcrTerminal(
      host: '192.168.1.50',
      serialNumber: 'P653200085189',
      transport: EcrTransport.wifi,
      config: EcrConfig(
        ecrId: 'TILL7',
        currencyCode: '512',
        minorUnitDigits: 3,
        port: 9100,
        connectTimeout: const Duration(seconds: 10),
        responseTimeout: const Duration(seconds: 120),
        probeTimeout: const Duration(seconds: 3),
      ),
      platform: MethodChannelAmwalEcr(channel: FakeEcrHost.channel),
    );
  });

  tearDown(() => host.dispose());

  group('the envelope every call carries', () {
    test('names the terminal, the transport and the operation', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      await terminal.sale(EcrAmount.parse('1.234'));

      final Map<Object?, Object?> args = host.argumentsOf(EcrMethods.sale);
      expect(args[EcrArgs.host], '192.168.1.50');
      expect(args[EcrArgs.serialNumber], 'P653200085189');
      expect(args[EcrArgs.transport], 'wifi');
      expect(args[EcrArgs.operationId], isA<String>());
      expect(args[EcrArgs.operationId], isNotEmpty);
    });

    test('gives every call its own operation id', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      await terminal.sale(EcrAmount.parse('1.000'));
      await terminal.sale(EcrAmount.parse('2.000'));

      expect(host.argumentValues(EcrArgs.operationId).toSet(), hasLength(2));
    });

    test('an operation id supplied by the caller is used as given', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      await terminal.sale(EcrAmount.parse('1.234'), operationId: 'till-7-0001');

      expect(
        host.argumentsOf(EcrMethods.sale)[EcrArgs.operationId],
        'till-7-0001',
      );
    });
  });

  group('config', () {
    test('crosses as a sub-map with durations in whole milliseconds', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      await terminal.sale(EcrAmount.parse('1.234'));

      final Map<Object?, Object?> config = host
          .argumentsOf(EcrMethods.sale)[EcrArgs.config]! as Map<Object?, Object?>;

      expect(config[EcrConfigKeys.ecrId], 'TILL7');
      expect(config[EcrConfigKeys.currencyCode], '512');
      expect(config[EcrConfigKeys.minorUnitDigits], 3);
      expect(config[EcrConfigKeys.port], 9100);
      expect(config[EcrConfigKeys.connectTimeoutMs], 10000);
      expect(config[EcrConfigKeys.responseTimeoutMs], 120000);
      expect(config[EcrConfigKeys.probeTimeoutMs], 3000);
    });

    test('numeric config fields are ints, never strings', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      await terminal.sale(EcrAmount.parse('1.234'));

      final Map<Object?, Object?> config = host
          .argumentsOf(EcrMethods.sale)[EcrArgs.config]! as Map<Object?, Object?>;

      expect(config[EcrConfigKeys.minorUnitDigits], isA<int>());
      expect(config[EcrConfigKeys.port], isA<int>());
      expect(config[EcrConfigKeys.connectTimeoutMs], isA<int>());
      expect(config[EcrConfigKeys.responseTimeoutMs], isA<int>());
      expect(config[EcrConfigKeys.probeTimeoutMs], isA<int>());
    });
  });

  group('the amount', () {
    test('crosses as a decimal string in MAJOR units, never a number', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      await terminal.sale(EcrAmount.parse('1.234'));

      final Object? amount = host.argumentsOf(EcrMethods.sale)[EcrArgs.amount];
      // Major units, and a string: 1.234 rial, not 1234 baisa and not a double
      // that cannot hold 1.234 in the first place. The host does the conversion
      // to minor units, once, using minorUnitDigits.
      expect(amount, '1.234');
      expect(amount, isA<String>());
      expect(amount, isNot(isA<num>()));
    });

    test('keeps trailing zeros, because a receipt shows what was written', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      await terminal.sale(EcrAmount.parse('1.200'));

      expect(host.argumentsOf(EcrMethods.sale)[EcrArgs.amount], '1.200');
    });

    test('is null — absent, not zero — for an operation that carries none', () async {
      host.answer(EcrMethods.voidTransaction, approvedPayload());

      await terminal.voidTransaction('215');

      // A void takes the original's amount. Sending "0" would be a different
      // statement, and one the terminal might act on.
      expect(
        host.argumentsOf(EcrMethods.voidTransaction)[EcrArgs.amount],
        isNull,
      );
    });
  });

  group('the fields that identify an earlier transaction', () {
    test('a void carries the receipt number, unpadded', () async {
      host.answer(EcrMethods.voidTransaction, approvedPayload());

      await terminal.voidTransaction('215', originalTerminalId: '31629');

      final Map<Object?, Object?> args =
          host.argumentsOf(EcrMethods.voidTransaction);
      // Unpadded on the channel: the host pads to the protocol's six digits, so
      // the padding rule lives in one place per platform rather than three.
      expect(args[EcrArgs.receiptNumber], '215');
      expect(args[EcrArgs.originalTerminalId], '31629');
    });

    test('a refund carries amount, receipt number and the original day', () async {
      host.answer(EcrMethods.refund, approvedPayload());

      await terminal.refund(
        EcrAmount.parse('0.216'),
        receiptNumber: '208',
        transactionDate: '20260809',
      );

      final Map<Object?, Object?> args = host.argumentsOf(EcrMethods.refund);
      expect(args[EcrArgs.amount], '0.216');
      expect(args[EcrArgs.receiptNumber], '208');
      expect(args[EcrArgs.transactionDate], '20260809');
    });

    test('originalTerminalId is empty, never null, when it is this terminal', () async {
      host.answer(EcrMethods.voidTransaction, approvedPayload());

      await terminal.voidTransaction('215');

      // Empty rather than null, matching the native SDKs' defaults: a host
      // reading null where it expected a string is a crash, and this field is
      // omitted from the wire message by emptiness, not by absence.
      expect(
        host.argumentsOf(EcrMethods.voidTransaction)[EcrArgs.originalTerminalId],
        '',
      );
    });

    test('an inquiry carries the receipt number and the day, and no amount', () async {
      host.answer(EcrMethods.inquire, <String, Object?>{
        EcrResultKeys.outcome: EcrOutcomes.notFound,
        EcrResultKeys.merchantReferenceId: 'A1',
        EcrResultKeys.responseMessage: 'no',
        EcrResultKeys.raw: '{}',
      });

      await terminal.inquire(receiptNumber: '208', transactionDate: '20260809');

      final Map<Object?, Object?> args = host.argumentsOf(EcrMethods.inquire);
      expect(args[EcrArgs.receiptNumber], '208');
      expect(args[EcrArgs.transactionDate], '20260809');
      expect(args[EcrArgs.amount], isNull);
    });
  });

  group('every key in the contract is present on every call', () {
    test('so a host can read a field without checking it exists first', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      await terminal.sale(EcrAmount.parse('1.234'));

      final Map<Object?, Object?> args = host.argumentsOf(EcrMethods.sale);
      for (final String key in EcrArgs.all) {
        expect(
          args.containsKey(key),
          isTrue,
          reason: '"$key" is in the contract but was not sent',
        );
      }
    });

    test('and nothing outside the contract is sent', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      await terminal.sale(EcrAmount.parse('1.234'));

      expect(
        host.argumentsOf(EcrMethods.sale).keys.toSet(),
        EcrArgs.all.toSet(),
      );
    });

    test('the config sub-map likewise carries exactly the contract keys', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      await terminal.sale(EcrAmount.parse('1.234'));

      final Map<Object?, Object?> config = host
          .argumentsOf(EcrMethods.sale)[EcrArgs.config]! as Map<Object?, Object?>;
      expect(config.keys.toSet(), EcrConfigKeys.all.toSet());
    });
  });

  group('each API call reaches the method the contract names', () {
    test('and no other', () async {
      for (final String method in <String>[
        EcrMethods.sale,
        EcrMethods.voidTransaction,
        EcrMethods.refund,
      ]) {
        host.answer(method, approvedPayload());
      }
      host.answer(EcrMethods.inquire, <String, Object?>{
        EcrResultKeys.outcome: EcrOutcomes.notFound,
        EcrResultKeys.merchantReferenceId: 'A1',
        EcrResultKeys.responseMessage: '',
        EcrResultKeys.raw: '{}',
      });
      host.answer(EcrMethods.receipt, <String, Object?>{
        EcrResultKeys.outcome: EcrOutcomes.unavailable,
        EcrResultKeys.merchantReferenceId: 'A1',
        EcrResultKeys.responseMessage: '',
        EcrResultKeys.raw: '{}',
      });
      host.answer(EcrMethods.isReachable, true);

      await terminal.isReachable();
      await terminal.sale(EcrAmount.parse('1.000'));
      await terminal.voidTransaction('215');
      await terminal.refund(
        EcrAmount.parse('1.000'),
        receiptNumber: '208',
        transactionDate: '20260809',
      );
      await terminal.inquire(receiptNumber: '208', transactionDate: '20260809');
      await terminal.receipt(receiptNumber: '208', transactionDate: '20260809');

      expect(host.methods, <String>[
        'isReachable',
        'sale',
        'void',
        'refund',
        'inquire',
        'receipt',
      ]);
    });
  });
}
