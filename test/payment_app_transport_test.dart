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

  EcrTerminal paymentApp() => EcrTerminal.appToApp(
        serialNumber: 'P653200085189',
        platform: MethodChannelAmwalEcr(channel: FakeEcrHost.channel),
      );

  setUp(() => host = FakeEcrHost());
  tearDown(() {
    host.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  group('which app takes the payment', () {
    test('is fixed, and is the Amwal payment app', () {
      expect(paymentApp().host, EcrPaymentApp.packageName);
      expect(EcrPaymentApp.packageName, 'com.amwalpay.pos');
      expect(paymentApp().transport, EcrTransport.appToApp);
    });

    test('cannot be pointed at another application', () {
      // There is no network in this transport, so nothing downstream would
      // notice a payment handed to the wrong app. It is refused here.
      expect(
        () => EcrTerminal(
          host: 'com.example.wallet',
          transport: EcrTransport.appToApp,
        ),
        throwsA(isA<EcrArgumentError>()),
      );
      expect(
        () => EcrTerminal(
          host: '192.168.1.50',
          transport: EcrTransport.appToApp,
        ),
        throwsA(isA<EcrArgumentError>()),
      );
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

    test('a receipt is fetched, as it is on every other local transport',
        () async {
      // The terminal keeps the same record and answers the same request. The
      // Kotlin SDK has always allowed this, and a terminal that behaved
      // differently depending on which SDK asked would be the one thing this
      // package exists to prevent.
      host.answers['receipt'] = (_) async => <String, Object?>{
            'outcome': 'ready',
            'merchantReference': 'ORDER-91',
            'url': 'https://receipts.amwalpay.om/r/abc',
            'raw': '',
          };

      final EcrReceipt receipt = await paymentApp().receipt(
        receiptNumber: '000123',
        transactionDate: '20260920',
      );

      expect(receipt, isA<EcrReceiptReady>());
      expect(host.countOf('receipt'), 1);
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
    test('local, and able to fetch a receipt like the others', () {
      final EcrOpenedSession session = EcrSessions.open(
        host: EcrPaymentApp.packageName,
        transport: EcrTransport.appToApp,
      );

      expect(session.usesLocalTerminal, isTrue);
      expect(session.usesPaymentApp, isTrue);
      expect(session.usesWebService, isFalse);
      expect(session.supportsReceipt, isTrue);
    });
  });
}
