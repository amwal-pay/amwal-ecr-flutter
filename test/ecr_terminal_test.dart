import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/amwal_ecr_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'platform/fake_host.dart';

/// The Dart API's own rules: what it refuses before anything is sent, and what
/// it does where the two platforms cannot do the same thing.
void main() {
  late FakeEcrHost host;

  EcrTerminal terminalOn(EcrTransport transport) => EcrTerminal(
        host: transport.isUsbCable ? '' : '192.168.1.50',
        serialNumber: 'P653200085189',
        transport: transport,
        platform: MethodChannelAmwalEcr(channel: FakeEcrHost.channel),
      );

  setUp(() => host = FakeEcrHost());
  tearDown(() => host.dispose());

  group('construction', () {
    test('a LAN terminal needs an address', () {
      expect(() => EcrTerminal(host: ''), throwsA(isA<EcrArgumentError>()));
      expect(() => EcrTerminal(host: '   '), throwsA(isA<EcrArgumentError>()));
    });

    test('Web Service does not require a host', () {
      expect(
        () => EcrTerminal(
          host: '',
          transport: EcrTransport.webService,
          config: EcrConfig(merchantId: '1', terminalId: '2'),
        ),
        returnsNormally,
      );
    });

    test('the config is checked at construction, not at the first sale', () {
      expect(() => EcrConfig(port: 0), throwsA(isA<EcrArgumentError>()));
      expect(() => EcrConfig(port: 70000), throwsA(isA<EcrArgumentError>()));
      expect(() => EcrConfig(minorUnitDigits: 5), throwsA(isA<EcrArgumentError>()));
      expect(
        () => EcrConfig(responseTimeout: Duration.zero),
        throwsA(isA<EcrArgumentError>()),
      );
    });

    test('the defaults describe an Omani deployment on the standard port', () {
      final EcrConfig config = EcrConfig();
      expect(config.ecrId, 'ECR01');
      expect(config.currencyCode, '512');
      expect(config.minorUnitDigits, 3);
      expect(config.port, 9100);
      expect(EcrConfig.defaultPort, 9100);
      // Generous on purpose: the cardholder has to present a card and may be
      // asked for a PIN.
      expect(config.responseTimeout, const Duration(seconds: 120));
      // Short on purpose: a terminal on the same network answers at once or is
      // not there at all.
      expect(config.probeTimeout, const Duration(seconds: 3));
    });

    test('copyWith replaces only what it names', () {
      final EcrConfig config = EcrConfig().copyWith(port: 9200, ecrId: 'TILL2');
      expect(config.port, 9200);
      expect(config.ecrId, 'TILL2');
      expect(config.minorUnitDigits, 3);
    });
  });

  group('what is refused before anything is sent', () {
    test('a sale with no amount cannot be expressed at all', () {
      // The typed method takes a required EcrAmount, so this is a compile-time
      // matter. The generic form is where it has to be checked.
      expect(
        () => terminalOn(EcrTransport.wifi).run(EcrTransactionType.sale),
        throwsA(isA<EcrArgumentError>()),
      );
      expect(host.calls, isEmpty);
    });

    test('a void with an amount is refused, because a void has no amount', () {
      // Accepting one would let a till believe it had voided part of a sale.
      expect(
        () => terminalOn(EcrTransport.wifi).run(
          EcrTransactionType.voidTransaction,
          amount: EcrAmount.parse('1.000'),
          receiptNumber: '215',
        ),
        throwsA(isA<EcrArgumentError>()),
      );
      expect(host.calls, isEmpty);
    });

    test('a void with no receipt number is refused', () {
      expect(
        () => terminalOn(EcrTransport.wifi).voidTransaction('  '),
        throwsA(isA<EcrArgumentError>()),
      );
      expect(host.calls, isEmpty);
    });

    test('an inquiry and a receipt each need a receipt number', () {
      final EcrTerminal terminal = terminalOn(EcrTransport.wifi);
      expect(
        () => terminal.inquire(receiptNumber: '', transactionDate: '20260809'),
        throwsA(isA<EcrArgumentError>()),
      );
      expect(
        () => terminal.receipt(receiptNumber: '', transactionDate: '20260809'),
        throwsA(isA<EcrArgumentError>()),
      );
      expect(host.calls, isEmpty);
    });

    test('a date in some other shape is refused', () {
      // Let through, this surfaces as "transaction not found" hours later.
      final EcrTerminal terminal = terminalOn(EcrTransport.wifi);
      for (final String bad in <String>['2026-08-09', '09082026x', '2026080']) {
        expect(
          () => terminal.inquire(receiptNumber: '208', transactionDate: bad),
          throwsA(isA<EcrArgumentError>()),
          reason: '"$bad" is not yyyyMMdd',
        );
      }
      expect(host.calls, isEmpty);
    });

    test('an absent date is allowed, matching the native SDKs', () async {
      host.answer(EcrMethods.receipt, <String, Object?>{
        EcrResultKeys.outcome: EcrOutcomes.unavailable,
        EcrResultKeys.merchantReference: 'A1',
        EcrResultKeys.responseMessage: '',
        EcrResultKeys.raw: '{}',
      });

      // The wire message simply leaves the field out rather than refusing.
      await terminalOn(EcrTransport.wifi)
          .receipt(receiptNumber: '215', transactionDate: '');

      expect(host.countOf(EcrMethods.receipt), 1);
    });

    test('run() refuses the read-only types and points at the right method', () {
      final EcrTerminal terminal = terminalOn(EcrTransport.wifi);

      expect(
        () => terminal.run(EcrTransactionType.inquiry, receiptNumber: '208'),
        throwsA(
          isA<EcrArgumentError>().having(
            (EcrArgumentError e) => e.message.toString(),
            'message',
            contains('inquire()'),
          ),
        ),
      );
      expect(
        () => terminal.run(EcrTransactionType.receipt, receiptNumber: '208'),
        throwsA(
          isA<EcrArgumentError>().having(
            (EcrArgumentError e) => e.message.toString(),
            'message',
            contains('receipt()'),
          ),
        ),
      );
    });
  });

  group('a transport with no listener', () {
    test('turns every money-moving operation into a typed failure', () async {
      final EcrResult result =
          await terminalOn(EcrTransport.bluetooth).sale(EcrAmount.parse('1.234'));

      expect(result, isA<EcrFailed>());
      expect((result as EcrFailed).failure, isA<EcrUnsupported>());
      expect(result.failure.message, contains('bluetooth'));
      expect(result.outcomeIsUnknown, isFalse);
    });

    test('webService money-moving operations reach the host', () async {
      host.answer(EcrMethods.sale, approvedPayload());
      final EcrTerminal terminal = EcrTerminal(
        host: '',
        serialNumber: 'P653200085189',
        transport: EcrTransport.webService,
        config: EcrConfig(
          merchantId: '13593',
          terminalId: '1',
          secureHashKey: '881dc200c9833da726e9376c2e32cff7',
        ),
        platform: MethodChannelAmwalEcr(channel: FakeEcrHost.channel),
      );
      await terminal.sale(EcrAmount.parse('1.234'));
      expect(host.methods, <String>['sale']);
    });

    test('and reaches the host not at all for bluetooth', () async {
      await terminalOn(EcrTransport.bluetooth).sale(EcrAmount.parse('1.234'));

      expect(host.calls, isEmpty);
    });

    test('an inquiry over it fails with its own type, not a sale\'s', () async {
      final EcrInquiry inquiry = await terminalOn(EcrTransport.bluetooth)
          .inquire(receiptNumber: '208', transactionDate: '20260809');

      expect(inquiry, isA<EcrInquiryFailed>());
      expect((inquiry as EcrInquiryFailed).failure, isA<EcrUnsupported>());
    });

    test('a receipt over it fails with its own type too', () async {
      final EcrReceipt receipt = await terminalOn(EcrTransport.webService)
          .receipt(receiptNumber: '215', transactionDate: '20260809');

      expect(receipt, isA<EcrReceiptFailed>());
      expect((receipt as EcrReceiptFailed).failure, isA<EcrUnsupported>());
    });

    test('isReachable answers false without spending the probe timeout', () async {
      expect(await terminalOn(EcrTransport.bluetooth).isReachable(), isFalse);
      expect(host.calls, isEmpty);
    });

    test('probeReachability answers locally for bluetooth', () async {
      final EcrReachability probe =
          await terminalOn(EcrTransport.bluetooth).probeReachability();

      expect(probe.reachable, isFalse);
      expect(probe.port, 0);
      expect(host.calls, isEmpty);
    });

    test('cancelling one is harmless and says nothing was running', () async {
      final EcrOperation<EcrResult> sale =
          terminalOn(EcrTransport.bluetooth).startSale(EcrAmount.parse('1.000'));

      expect(await sale.cancel(), isFalse);
      expect((await sale.result as EcrFailed).failure, isA<EcrUnsupported>());
    });
  });

  group('local transports go through', () {
    test('usbCable and wifi both reach the host', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      host.answer(EcrMethods.sale, approvedPayload());

      await terminalOn(EcrTransport.usbCable).sale(EcrAmount.parse('1.000'));
      await terminalOn(EcrTransport.wifi).sale(EcrAmount.parse('1.000'));

      expect(host.countOf(EcrMethods.sale), 2);
      expect(
        host.argumentValues(EcrArgs.transport),
        <String>['usb_cable', 'wifi'],
      );
    });

    test('usbCable allows an empty host', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        () => EcrTerminal(host: '', transport: EcrTransport.usbCable),
        returnsNormally,
      );
    });

    test('wifi is the default, being the one an operator can read off screen', () {
      expect(EcrTerminal(host: '10.0.0.1').transport, EcrTransport.wifi);
    });
  });

  group('run() drives the type from a menu', () {
    test('and reaches the same methods the typed calls do', () async {
      for (final String method in <String>[
        EcrMethods.sale,
        EcrMethods.voidTransaction,
        EcrMethods.refund,
      ]) {
        host.answer(method, approvedPayload());
      }

      final EcrTerminal terminal = terminalOn(EcrTransport.wifi);
      await terminal.run(
        EcrTransactionType.sale,
        amount: EcrAmount.parse('1.000'),
      );
      await terminal.run(
        EcrTransactionType.voidTransaction,
        receiptNumber: '215',
      );
      await terminal.run(
        EcrTransactionType.refund,
        amount: EcrAmount.parse('1.000'),
        receiptNumber: '208',
        transactionDate: '20260809',
      );

      expect(host.methods, <String>['sale', 'void', 'refund']);
    });
  });
}
