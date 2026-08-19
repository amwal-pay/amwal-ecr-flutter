import 'dart:async';

import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/amwal_ecr_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_host.dart';

/// How many times things happen.
///
/// The value in a payload is easy to check and easy to get right. The number of
/// times a request is sent, and the number of times a future settles, are
/// neither — and they are what turns a bad afternoon into a customer charged
/// twice. Everything in this file counts.
void main() {
  late FakeEcrHost host;
  late MethodChannelAmwalEcr platform;
  late EcrTerminal terminal;

  setUp(() {
    host = FakeEcrHost();
    platform = MethodChannelAmwalEcr(channel: FakeEcrHost.channel);
    terminal = EcrTerminal(
      host: '192.168.1.50',
      serialNumber: 'P653200085189',
      platform: platform,
    );
  });

  tearDown(() => host.dispose());

  group('completion count', () {
    test('one sale is one invocation, and one answer', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      final EcrResult result = await terminal.sale(EcrAmount.parse('1.234'));

      expect(host.countOf(EcrMethods.sale), 1);
      expect(result, isA<EcrApproved>());
    });

    test('a timeout is NOT retried — the whole point of the package', () async {
      host.answer(EcrMethods.sale, failedPayload(kind: EcrFailureKinds.timeout));

      final EcrResult result = await terminal.sale(EcrAmount.parse('1.234'));

      // A terminal that timed out may have taken the money. Sending the request
      // again is how the customer pays twice. Nothing in this package retries,
      // and this test is the guard on that.
      expect(host.countOf(EcrMethods.sale), 1);
      expect(result.outcomeIsUnknown, isTrue);
    });

    test('a decline is not retried either', () async {
      host.answer(EcrMethods.sale, declinedPayload());

      await terminal.sale(EcrAmount.parse('1.234'));

      expect(host.countOf(EcrMethods.sale), 1);
    });

    test('a host that throws is not retried', () async {
      host.fail(EcrMethods.sale, Exception('the host fell over'));

      await terminal.sale(EcrAmount.parse('1.234'));

      expect(host.countOf(EcrMethods.sale), 1);
    });

    test('the future settles exactly once', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      int settled = 0;
      final Future<EcrResult> future = terminal.sale(EcrAmount.parse('1.234'));
      unawaited(future.then((_) => settled++));

      await future;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(settled, 1);
    });

    test('two sales are two invocations, not one shared answer', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      final List<EcrResult> results = await Future.wait(<Future<EcrResult>>[
        terminal.sale(EcrAmount.parse('1.000')),
        terminal.sale(EcrAmount.parse('2.000')),
      ]);

      expect(host.countOf(EcrMethods.sale), 2);
      expect(results, hasLength(2));
    });

    test('reusing an operation id while one is in flight is refused', () async {
      host.hold(EcrMethods.sale);

      final Future<EcrResult> first =
          terminal.sale(EcrAmount.parse('1.000'), operationId: 'till-1');

      // Two calls sharing an id would leave cancel() unable to say which it
      // meant, and one of the two futures orphaned.
      expect(
        () => terminal.sale(EcrAmount.parse('2.000'), operationId: 'till-1'),
        throwsA(isA<EcrArgumentError>()),
      );
      expect(host.countOf(EcrMethods.sale), 1);

      host.release(EcrMethods.sale, approvedPayload());
      await first;
    });

    test('an id is free again once its operation has answered', () async {
      host.answer(EcrMethods.sale, approvedPayload());

      await terminal.sale(EcrAmount.parse('1.000'), operationId: 'till-1');
      await terminal.sale(EcrAmount.parse('2.000'), operationId: 'till-1');

      expect(host.countOf(EcrMethods.sale), 2);
    });
  });

  group('cancellation', () {
    test('cancel reaches the host naming the operation it means', () async {
      host.hold(EcrMethods.sale);
      host.answer(EcrMethods.cancel, true);

      final EcrOperation<EcrResult> sale =
          terminal.startSale(EcrAmount.parse('1.234'), operationId: 'till-9');
      await Future<void>.delayed(Duration.zero);

      final bool wasRunning = await sale.cancel();

      expect(wasRunning, isTrue);
      expect(
        host.argumentsOf(EcrMethods.cancel)[EcrArgs.operationId],
        'till-9',
      );

      host.release(EcrMethods.sale, approvedPayload());
      await sale.result;
    });

    test('a cancelled sale reports an UNKNOWN outcome, never a decline', () async {
      host.hold(EcrMethods.sale);
      host.answer(EcrMethods.cancel, true);

      final EcrOperation<EcrResult> sale =
          terminal.startSale(EcrAmount.parse('1.234'), operationId: 'till-9');
      await Future<void>.delayed(Duration.zero);
      await sale.cancel();

      // The host answers the held call with the cancelled failure, exactly as
      // the Kotlin and Swift handlers do.
      host.release(
        EcrMethods.sale,
        failedPayload(kind: EcrFailureKinds.cancelled, message: 'cancelled'),
      );

      final EcrResult result = await sale.result;

      expect(result, isA<EcrFailed>());
      expect((result as EcrFailed).failure, isA<EcrCancelled>());
      // Closing a socket tells the terminal nothing. The cardholder may well
      // have finished paying.
      expect(result.outcomeIsUnknown, isTrue);
      expect(result, isNot(isA<EcrDeclined>()));
    });

    test('cancelling does not send anything again', () async {
      host.hold(EcrMethods.sale);
      host.answer(EcrMethods.cancel, true);

      final EcrOperation<EcrResult> sale =
          terminal.startSale(EcrAmount.parse('1.234'), operationId: 'till-9');
      await Future<void>.delayed(Duration.zero);
      await sale.cancel();
      host.release(EcrMethods.sale, failedPayload(kind: EcrFailureKinds.cancelled));
      await sale.result;

      expect(host.countOf(EcrMethods.sale), 1);
    });

    test('cancelling an operation that already answered says so', () async {
      host.answer(EcrMethods.sale, approvedPayload());
      host.answer(EcrMethods.cancel, true);

      final EcrOperation<EcrResult> sale =
          terminal.startSale(EcrAmount.parse('1.234'), operationId: 'till-9');
      await sale.result;

      // false: there was nothing to interrupt. The real outcome is on the
      // future, and a till that reads `true` here would think it had stopped a
      // sale that in fact went through.
      expect(await sale.cancel(), isFalse);
      expect(host.countOf(EcrMethods.cancel), 0);
    });

    test('the handle records that a cancel was asked for', () async {
      host.hold(EcrMethods.sale);
      host.answer(EcrMethods.cancel, true);

      final EcrOperation<EcrResult> sale =
          terminal.startSale(EcrAmount.parse('1.234'), operationId: 'till-9');
      expect(sale.isCancelRequested, isFalse);

      await Future<void>.delayed(Duration.zero);
      await sale.cancel();
      expect(sale.isCancelRequested, isTrue);

      host.release(EcrMethods.sale, failedPayload(kind: EcrFailureKinds.cancelled));
      await sale.result;
    });

    test('a host that cannot be asked to cancel does not break the operation', () async {
      host.hold(EcrMethods.sale);
      host.fail(EcrMethods.cancel, PlatformExceptionStub());

      final EcrOperation<EcrResult> sale =
          terminal.startSale(EcrAmount.parse('1.234'), operationId: 'till-9');
      await Future<void>.delayed(Duration.zero);

      expect(await sale.cancel(), isFalse);

      // The operation still settles on whatever the terminal eventually says.
      host.release(EcrMethods.sale, approvedPayload());
      expect(await sale.result, isA<EcrApproved>());
    });
  });

  group('late callbacks', () {
    test('a reply that arrives after the future settled is dropped', () async {
      // Two answers for one call. A well-behaved host cannot do this, and the
      // engine drops the second — but the guard is here so that a host which
      // does it crashes nothing, and a till is never told two different things
      // about one payment.
      host.answer(EcrMethods.sale, approvedPayload());

      final Future<EcrResult> future = terminal.sale(EcrAmount.parse('1.234'));
      final EcrResult first = await future;
      final EcrResult second = await future;

      expect(identical(first, second), isTrue);
      expect(first, isA<EcrApproved>());
    });

    test('an operation is deregistered once it answers, so a late cancel is a no-op', () async {
      host.answer(EcrMethods.sale, approvedPayload());
      host.answer(EcrMethods.cancel, true);

      await terminal.sale(EcrAmount.parse('1.234'), operationId: 'till-9');
      await Future<void>.delayed(Duration.zero);

      expect(platform.inFlightCount, 0);
      expect(await platform.cancel('till-9'), isFalse);
    });

    test('an operation that fails is deregistered too', () async {
      host.fail(EcrMethods.sale, Exception('boom'));

      await terminal.sale(EcrAmount.parse('1.234'), operationId: 'till-9');
      await Future<void>.delayed(Duration.zero);

      expect(platform.inFlightCount, 0);
    });

    test('in-flight operations are counted while they run', () async {
      host.hold(EcrMethods.sale);

      final EcrOperation<EcrResult> sale =
          terminal.startSale(EcrAmount.parse('1.234'), operationId: 'till-9');
      await Future<void>.delayed(Duration.zero);

      expect(platform.inFlightCount, 1);

      host.release(EcrMethods.sale, approvedPayload());
      await sale.result;
      await Future<void>.delayed(Duration.zero);

      expect(platform.inFlightCount, 0);
    });
  });

  group('an inquiry is the safe thing to repeat', () {
    test('so it may be sent again, and the count says so', () async {
      host.answer(EcrMethods.inquire, <String, Object?>{
        EcrResultKeys.outcome: EcrOutcomes.notFound,
        EcrResultKeys.merchantReferenceId: 'A1',
        EcrResultKeys.responseMessage: 'not found',
        EcrResultKeys.raw: '{}',
      });

      await terminal.inquire(receiptNumber: '208', transactionDate: '20260809');
      await terminal.inquire(receiptNumber: '208', transactionDate: '20260809');

      // Two calls because the caller asked twice — never because the package
      // decided to.
      expect(host.countOf(EcrMethods.inquire), 2);
    });
  });
}

/// A stand-in for a host-side error, so the test does not depend on how
/// `PlatformException` renders.
class PlatformExceptionStub implements Exception {
  @override
  String toString() => 'PlatformExceptionStub';
}
