import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/amwal_ecr_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'platform/fake_host.dart';

/// The transport where the terminal is this device.
///
/// What is worth checking here is mostly what does *not* happen: a till on a
/// platform that cannot start the payment app must be told so without anything
/// being sent, and the one operation that settles an unknown outcome must
/// never be refused locally.
void main() {
  late FakeEcrHost host;

  EcrTerminal paymentApp({String? packageName}) => EcrTerminal.appToApp(
        serialNumber: 'P653200085189',
        packageName: packageName ?? EcrPaymentApp.defaultPackage,
        platform: MethodChannelAmwalEcr(channel: FakeEcrHost.channel),
      );

  setUp(() => host = FakeEcrHost());
  tearDown(() {
    host.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  group('naming the payment app', () {
    test('the default is the terminal build', () {
      expect(paymentApp().host, 'com.amwalpay.pos');
      expect(paymentApp().transport, EcrTransport.appToApp);
    });

    test('another application id can be driven, for a test build', () {
      expect(paymentApp(packageName: 'com.amwalpay.pos.uat').host,
          'com.amwalpay.pos.uat');
    });

    test('an address where an application id belongs is refused at once', () {
      // A till that passed an IP here would otherwise only find out at the
      // first sale, with a cardholder waiting.
      expect(
        () => EcrTerminal.appToApp(packageName: '192.168.1.50'),
        throwsA(isA<EcrArgumentError>()),
      );
      expect(
        () => EcrTerminal(host: 'not-a-package', transport: EcrTransport.appToApp),
        throwsA(isA<EcrArgumentError>()),
      );
    });

    test('an empty name falls back rather than failing', () {
      expect(paymentApp(packageName: '   ').host, 'com.amwalpay.pos');
    });
  });

  group('on a platform that cannot start it', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('a sale is refused, and nothing is sent', () async {
      final EcrResult result = await paymentApp().sale(
        EcrAmount.parse('10.500'),
        merchantReference: 'ORDER-91',
      );

      expect(result, isA<EcrFailed>());
      final EcrFailed failed = result as EcrFailed;
      expect(failed.failure, isA<EcrUnsupported>());
      // Nothing was attempted, so there is nothing to reconcile.
      expect(failed.outcomeIsUnknown, isFalse);
      expect(host.calls, isEmpty);
    });

    test('the reason says it is the platform, not the network', () async {
      final EcrResult result = await paymentApp().sale(
        EcrAmount.parse('10.500'),
        merchantReference: 'ORDER-91',
      );

      final EcrFailed failed = result as EcrFailed;
      expect(failed.failure.message, contains('Android intent'));
      expect(failed.failure.message, contains('nothing was sent'));
      // "the port stays closed" would send an integrator looking for a
      // network problem that does not exist here.
      expect(failed.failure.message, isNot(contains('port')));
    });

    test('a probe answers without sending anything', () async {
      final EcrReachability reachability =
          await paymentApp().probeReachability();

      expect(reachability.reachable, isFalse);
      expect(host.calls, isEmpty);
    });
  });

  group('on Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('a probe reaches the host, because it can be answered there', () async {
      host.answers['probeReachability'] = (_) async => <String, Object?>{
            'reachable': true,
            'host': 'com.amwalpay.pos',
            'port': 0,
            'endpoint': 'com.amwalpay.pos',
          };

      final EcrReachability reachability =
          await paymentApp().probeReachability();

      expect(reachability.reachable, isTrue);
      expect(host.countOf('probeReachability'), 1);
    });

    test('an inquiry by reference is never refused here', () async {
      // The one way out of an unknown outcome. Refusing it locally would
      // leave a till holding a transaction it can never settle.
      host.answers['inquireByReference'] = (_) async => <String, Object?>{
            'outcome': 'notFound',
            'merchantReference': 'ORDER-91',
            'reason': 'no record',
            'raw': '',
          };

      final EcrInquiry inquiry =
          await paymentApp().inquireByReference('ORDER-91');

      expect(inquiry, isA<EcrInquiryNotFound>());
      expect(host.countOf('inquireByReference'), 1);
    });

    test('a receipt is refused, and not attempted', () async {
      final EcrReceipt receipt = await paymentApp().receipt(
        receiptNumber: '000123',
        transactionDate: '20260920',
      );

      expect(receipt, isA<EcrReceiptFailed>());
      expect(host.calls, isEmpty);
    });

    test('a sale is sent once', () async {
      host.answers['sale'] = (_) async => <String, Object?>{
            'outcome': 'approved',
            'merchantReference': 'ORDER-91',
            'amount': '10.500',
            'responseCode': '00',
          };

      final EcrResult result = await paymentApp().sale(
        EcrAmount.parse('10.500'),
        merchantReference: 'ORDER-91',
      );

      expect(result, isA<EcrApproved>());
      expect(host.countOf('sale'), 1);
      expect(
        host.calls.single.arguments['transport'],
        'app_to_app',
      );
      // The application id travels where an address would, so nothing outside
      // the channel contract is sent.
      expect(host.calls.single.arguments['host'], 'com.amwalpay.pos');
    });
  });

  group('the session names what it is', () {
    test('local, but not a receipt fetcher', () {
      final EcrOpenedSession session = EcrSessions.open(
        host: EcrPaymentApp.defaultPackage,
        transport: EcrTransport.appToApp,
      );

      expect(session.usesLocalTerminal, isTrue);
      expect(session.usesPaymentApp, isTrue);
      expect(session.usesWebService, isFalse);
      expect(session.supportsReceipt, isFalse);
    });
  });
}
