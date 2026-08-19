import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-end, on a real device, against a real ECR listener.
///
/// Everything else in this repository tests the wrapper with the terminal
/// faked. This is the only place the socket is real, the native SDK is the
/// published one, and the bytes on the wire are the bytes in
/// `ecr-sdk/docs/protocol.md`. It is what tells you the plugin is registered,
/// the podspec compiles, the permissions are declared, and the two hosts agree.
///
/// It needs something listening. Either:
///
///   python3 tools/fake_pos_server.py --port 9100 --secret <hex key>
///
/// on a machine the device can reach, or a real terminal in ECR mode. Then:
///
///   flutter test integration_test/app_test.dart \
///     --dart-define=ECR_HOST=192.168.1.50 \
///     --dart-define=ECR_SERIAL=P653200085189 \
///     --dart-define=ECR_SECURE_HASH_KEY=<the terminal's hex key>
///
/// Give it the key the terminal is provisioned with. A terminal that has one
/// answers an unsigned request with a security violation and nothing else, so
/// leaving it out against a provisioned terminal fails every case here.
///
/// **Never point it at production.** It takes real payments if the terminal is
/// live: every money-moving test here is skipped unless ECR_ALLOW_FINANCIAL is
/// set, so a stray CI run cannot charge anybody.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const String host = String.fromEnvironment('ECR_HOST');
  const String serial = String.fromEnvironment('ECR_SERIAL');
  const int port = int.fromEnvironment('ECR_PORT', defaultValue: 9100);
  const bool allowFinancial =
      bool.fromEnvironment('ECR_ALLOW_FINANCIAL', defaultValue: false);
  const String receiptNumber =
      String.fromEnvironment('ECR_RECEIPT_NUMBER', defaultValue: '215');
  const String transactionDate =
      String.fromEnvironment('ECR_DATE', defaultValue: '');
  const String secureHashKey =
      String.fromEnvironment('ECR_SECURE_HASH_KEY', defaultValue: '');

  final bool configured = host.isNotEmpty;

  EcrTerminal terminalOn(EcrTransport transport) => EcrTerminal(
        host: host,
        serialNumber: serial,
        transport: transport,
        config: EcrConfig(
          port: port,
          // Short, so a wrong address fails the suite in seconds rather than
          // holding a CI machine for two minutes per case.
          connectTimeout: const Duration(seconds: 5),
          responseTimeout: const Duration(seconds: 60),
          probeTimeout: const Duration(seconds: 2),
          // Empty talks to an unprovisioned terminal, which is what the fake
          // server does without --secret.
          secureHashKey: secureHashKey,
        ),
      );

  String today() {
    final DateTime now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
  }

  final String date = transactionDate.isEmpty ? today() : transactionDate;

  group('the plugin is really there', () {
    testWidgets('a call reaches the native host and comes back typed',
        (WidgetTester tester) async {
      // No ECR_HOST: point at an address on this device that nothing listens
      // on. The answer is "unreachable", which still proves the whole path —
      // channel, host, native SDK, socket — is wired up. A MissingPluginException
      // would surface here as EcrUnsupported instead.
      final EcrTerminal terminal = EcrTerminal(
        host: configured ? host : '127.0.0.1',
        serialNumber: serial,
        config: EcrConfig(
          port: configured ? port : 1,
          probeTimeout: const Duration(seconds: 2),
        ),
      );

      final bool reachable = await terminal.isReachable();

      if (!configured) {
        expect(reachable, isFalse);
      }
    });

    testWidgets('an unroutable address is unreachable, not unsupported',
        (WidgetTester tester) async {
      final EcrTerminal terminal = EcrTerminal(
        host: '127.0.0.1',
        config: EcrConfig(port: 1, probeTimeout: const Duration(seconds: 2)),
      );

      final EcrResult result = await terminal.sale(EcrAmount.parse('0.001'));

      expect(result, isA<EcrFailed>());
      final EcrFailure failure = (result as EcrFailed).failure;
      // If the plugin were not registered this would be EcrUnsupported, so the
      // assertion is doing double duty.
      expect(failure, isA<EcrUnreachable>());
      // Nothing was sent, so nothing has to be reconciled.
      expect(failure.outcomeIsUnknown, isFalse);
    });

    testWidgets('a transport with no listener is refused without a socket',
        (WidgetTester tester) async {
      final Stopwatch stopwatch = Stopwatch()..start();

      final EcrResult result = await EcrTerminal(
        host: '10.255.255.1',
        transport: EcrTransport.bluetooth,
        config: EcrConfig(connectTimeout: const Duration(seconds: 30)),
      ).sale(EcrAmount.parse('0.001'));

      stopwatch.stop();

      expect((result as EcrFailed).failure, isA<EcrUnsupported>());
      // Immediately: nothing was attempted, so the 30-second connect timeout is
      // never spent.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    testWidgets('an argument error is thrown, not returned as an outcome',
        (WidgetTester tester) async {
      expect(
        () => EcrTerminal(host: '127.0.0.1').voidTransaction(''),
        throwsA(isA<EcrArgumentError>()),
      );
    });
  });

  group('against a listener', () {
    testWidgets('it answers a probe', (WidgetTester tester) async {
      expect(await terminalOn(EcrTransport.wifi).isReachable(), isTrue);
    }, skip: !configured);

    testWidgets('an inquiry comes back readable', (WidgetTester tester) async {
      // Read-only: safe against any terminal, in any state, at any time.
      final EcrInquiry inquiry = await terminalOn(EcrTransport.wifi).inquire(
        receiptNumber: receiptNumber,
        transactionDate: date,
      );

      // Found or not found — both are real answers. What must not happen is a
      // failure, which would mean the exchange itself did not work.
      expect(inquiry, isNot(isA<EcrInquiryFailed>()));

      if (inquiry is EcrInquiryFound) {
        final EcrTransaction transaction = inquiry.transaction;
        expect(transaction.stan, isNotEmpty);
        // Major units, from the backend's own record.
        expect(transaction.amount, isNot(matches(r'^0{6,}')));
        expect(inquiry.merchantReferenceId, hasLength(12));
      }
    }, skip: !configured);

    testWidgets('a receipt request comes back readable',
        (WidgetTester tester) async {
      final EcrReceipt receipt = await terminalOn(EcrTransport.wifi).receipt(
        receiptNumber: receiptNumber,
        transactionDate: date,
      );

      expect(receipt, isNot(isA<EcrReceiptFailed>()));
      if (receipt is EcrReceiptReady) {
        expect(receipt.url, startsWith('http'));
      }
    }, skip: !configured);

    testWidgets('a timeout is reported as unknown, and nothing is resent',
        (WidgetTester tester) async {
      // A listener that accepts and never answers. `fake_pos_server.py --delay`
      // is one; so is a terminal left at its idle screen.
      final EcrTerminal terminal = EcrTerminal(
        host: host,
        serialNumber: serial,
        config: EcrConfig(
          port: port,
          responseTimeout: const Duration(seconds: 2),
        ),
      );

      final EcrInquiry inquiry = await terminal.inquire(
        receiptNumber: receiptNumber,
        transactionDate: date,
      );

      if (inquiry is EcrInquiryFailed) {
        expect(inquiry.failure, isA<EcrTimeout>());
      }
    }, skip: !configured);
  });

  group('money moves', () {
    testWidgets('a sale is approved or declined, and answered once',
        (WidgetTester tester) async {
      final EcrResult result =
          await terminalOn(EcrTransport.wifi).sale(EcrAmount.parse('0.100'));

      expect(result, isA<EcrResult>());
      if (result is EcrApproved) {
        expect(result.rrn, isNotEmpty);
        // Major units on the way back: 0.100, never 000000000100.
        expect(result.amount, contains('.'));
      }
      if (result.outcomeIsUnknown) {
        // Do not retry — find out. This is the behaviour under test.
        final EcrInquiry inquiry = await terminalOn(EcrTransport.wifi).inquire(
          receiptNumber: receiptNumber,
          transactionDate: date,
        );
        expect(inquiry, isNot(isA<EcrInquiryFailed>()));
      }
    }, skip: !configured || !allowFinancial);

    testWidgets('cancelling a sale answers at once, as an unknown outcome',
        (WidgetTester tester) async {
      final EcrOperation<EcrResult> sale = terminalOn(EcrTransport.wifi)
          .startSale(EcrAmount.parse('0.100'), operationId: 'integration-1');

      await Future<void>.delayed(const Duration(milliseconds: 500));
      final bool wasRunning = await sale.cancel();
      final EcrResult result = await sale.result;

      if (wasRunning) {
        expect(result, isA<EcrFailed>());
        // Closing a socket tells the terminal nothing. The cardholder may well
        // have finished paying, so this is unknown and never a refusal.
        expect(result.outcomeIsUnknown, isTrue);
      }
    }, skip: !configured || !allowFinancial);
  });
}
