import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/amwal_ecr_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_host.dart';

/// Every way an operation can end, and what the caller is told.
///
/// The dividing line the whole package is built around runs through this file:
/// **did we learn what happened?** A decline is knowledge. A timeout is not.
/// Anything that mistakes the second for the first ends with a customer paying
/// twice, so every case here asserts `outcomeIsUnknown` as well as the type.
void main() {
  late FakeEcrHost host;
  late EcrTerminal terminal;

  setUp(() {
    host = FakeEcrHost();
    terminal = EcrTerminal(
      host: '192.168.1.50',
      platform: MethodChannelAmwalEcr(channel: FakeEcrHost.channel),
    );
  });

  tearDown(() => host.dispose());

  Future<EcrResult> sale() => terminal.sale(EcrAmount.parse('1.234'));

  group('the four native failure kinds', () {
    test('unreachable — nothing was sent, so a retry is safe', () async {
      host.answer(
        EcrMethods.sale,
        failedPayload(kind: EcrFailureKinds.unreachable, message: 'no route'),
      );

      final EcrResult result = await sale();

      expect(result, isA<EcrFailed>());
      expect((result as EcrFailed).failure, isA<EcrUnreachable>());
      expect(result.failure.message, 'no route');
      expect(result.outcomeIsUnknown, isFalse);
    });

    test('timeout — the terminal may have taken the money', () async {
      host.answer(EcrMethods.sale, failedPayload(kind: EcrFailureKinds.timeout));

      final EcrResult result = await sale();

      expect((result as EcrFailed).failure, isA<EcrTimeout>());
      expect(result.outcomeIsUnknown, isTrue);
    });

    test('malformed — the terminal answered, illegibly', () async {
      host.answer(
        EcrMethods.sale,
        failedPayload(kind: EcrFailureKinds.malformed, message: 'not JSON'),
      );

      final EcrResult result = await sale();

      expect((result as EcrFailed).failure, isA<EcrMalformed>());
      // It answered, so it acted. What it did is simply not legible.
      expect(result.outcomeIsUnknown, isTrue);
    });

    test('connection lost — unknown, like a timeout', () async {
      host.answer(
        EcrMethods.sale,
        failedPayload(kind: EcrFailureKinds.connectionLost, message: 'closed'),
      );

      final EcrResult result = await sale();

      expect((result as EcrFailed).failure, isA<EcrConnectionLost>());
      expect(result.outcomeIsUnknown, isTrue);
    });
  });

  group('the two wrapper-level failure kinds', () {
    test('cancelled — unknown, and says so in its own message', () async {
      host.answer(
        EcrMethods.sale,
        failedPayload(kind: EcrFailureKinds.cancelled, message: ''),
      );

      final EcrResult result = await sale();

      expect((result as EcrFailed).failure, isA<EcrCancelled>());
      expect(result.outcomeIsUnknown, isTrue);
      // An empty message from the host falls back to the warning that matters.
      expect(result.failure.message, contains('inquire before retrying'));
    });

    test('unsupported — nothing was attempted', () async {
      host.answer(
        EcrMethods.sale,
        failedPayload(
          kind: EcrFailureKinds.unsupported,
          message: 'not over bluetooth',
        ),
      );

      final EcrResult result = await sale();

      expect((result as EcrFailed).failure, isA<EcrUnsupported>());
      expect(result.outcomeIsUnknown, isFalse);
    });
  });

  group('a failure this version has never heard of', () {
    test('is read as unknown, not guessed at', () async {
      host.answer(
        EcrMethods.sale,
        failedPayload(kind: 'quantum-entanglement-lost', message: 'oh dear'),
      );

      final EcrResult result = await sale();

      // A newer host reporting a failure this build does not know must not be
      // read as a refusal. Unknown is the only safe reading.
      expect((result as EcrFailed).failure, isA<EcrMalformed>());
      expect(result.outcomeIsUnknown, isTrue);
      expect(result.failure.message, contains('quantum-entanglement-lost'));
      expect(result.failure.message, contains('oh dear'));
    });

    test('an outcome this version has never heard of is likewise unknown', () async {
      host.answer(EcrMethods.sale, <String, Object?>{
        EcrResultKeys.outcome: 'partially-settled',
        EcrResultKeys.merchantReferenceId: 'A1B2C3D4E5F6',
      });

      final EcrResult result = await sale();

      expect(result, isA<EcrFailed>());
      expect(result.outcomeIsUnknown, isTrue);
      expect((result as EcrFailed).failure.message, contains('partially-settled'));
    });
  });

  group('host-level errors', () {
    test('an invalid-argument error is thrown, because nothing was sent', () async {
      host.fail(
        EcrMethods.sale,
        PlatformException(
          code: EcrErrorCodes.invalidArgument,
          message: 'This operation needs an amount',
        ),
      );

      // An exception rather than an outcome: the request never left the device,
      // so there is nothing to reconcile and nothing for a till to book.
      await expectLater(
        sale(),
        throwsA(
          isA<EcrArgumentError>().having(
            (EcrArgumentError e) => e.message,
            'message',
            'This operation needs an amount',
          ),
        ),
      );
    });

    test('any other host error is an unknown outcome, never a decline', () async {
      host.fail(
        EcrMethods.sale,
        PlatformException(code: EcrErrorCodes.internal, message: 'NPE'),
      );

      final EcrResult result = await sale();

      expect(result, isA<EcrFailed>());
      expect(result.outcomeIsUnknown, isTrue);
      expect((result as EcrFailed).failure.message, contains('NPE'));
    });

    test('a missing plugin is reported as unsupported, with the fix', () async {
      // No answer registered: FakeEcrHost throws MissingPluginException, which
      // is what a real app gets when the plugin was added without a rebuild.
      final EcrResult result = await sale();

      expect((result as EcrFailed).failure, isA<EcrUnsupported>());
      expect(result.outcomeIsUnknown, isFalse);
      expect(result.failure.message, contains('rebuild'));
    });

    test('isReachable answers false rather than throwing on a host error', () async {
      host.fail(EcrMethods.isReachable, PlatformException(code: 'whatever'));

      // An unreachable terminal is an answer. A probe that throws would make
      // every caller wrap it, and one of them would forget.
      expect(await terminal.isReachable(), isFalse);
    });

    test('isReachable still throws on a bad argument', () async {
      host.fail(
        EcrMethods.isReachable,
        PlatformException(
          code: EcrErrorCodes.invalidArgument,
          message: '"host" is required',
        ),
      );

      await expectLater(
        terminal.isReachable(),
        throwsA(isA<EcrArgumentError>()),
      );
    });
  });

  group('a payload that is wrong in every way a real host might get it wrong', () {
    test('a null answer is an unknown outcome', () async {
      host.answer(EcrMethods.sale, null);

      final EcrResult result = await sale();

      expect(result, isA<EcrFailed>());
      expect(result.outcomeIsUnknown, isTrue);
    });

    test('a missing failure sub-map is an unknown outcome', () async {
      host.answer(EcrMethods.sale, <String, Object?>{
        EcrResultKeys.outcome: EcrOutcomes.failed,
        EcrResultKeys.merchantReferenceId: 'A1',
      });

      final EcrResult result = await sale();

      expect((result as EcrFailed).failure, isA<EcrMalformed>());
      expect(result.outcomeIsUnknown, isTrue);
    });

    test('nulls where strings were promised read as empty, not as "null"', () async {
      host.answer(EcrMethods.sale, <String, Object?>{
        EcrResultKeys.outcome: EcrOutcomes.approved,
        EcrResultKeys.merchantReferenceId: 'A1B2C3D4E5F6',
        EcrResultKeys.amount: '1.234',
        EcrResultKeys.responseCode: '00',
        EcrResultKeys.rrn: null,
        EcrResultKeys.authCode: null,
        EcrResultKeys.maskedPan: null,
        EcrResultKeys.partialApproval: null,
        EcrResultKeys.requestedAmount: null,
        EcrResultKeys.raw: null,
      });

      final EcrResult result = await sale();

      final EcrApproved approved = result as EcrApproved;
      expect(approved.rrn, '');
      expect(approved.authCode, '');
      expect(approved.maskedPan, '');
      expect(approved.requestedAmount, '');
      expect(approved.raw, '');
      expect(approved.partialApproval, isFalse);
    });

    test('an approved payload with no fields at all still reads', () async {
      host.answer(EcrMethods.sale, <String, Object?>{
        EcrResultKeys.outcome: EcrOutcomes.approved,
      });

      final EcrResult result = await sale();

      expect(result, isA<EcrApproved>());
      expect(result.merchantReferenceId, '');
      expect((result as EcrApproved).amount, '');
    });
  });

  group('the response codes that mean something particular', () {
    test('96 — the terminal was busy; nothing was attempted', () async {
      host.answer(
        EcrMethods.sale,
        declinedPayload(responseCode: '96', reason: 'A transaction is running'),
      );

      final EcrResult result = await sale();
      final EcrDeclined declined = result as EcrDeclined;

      expect(declined.isTerminalBusy, isTrue);
      expect(declined.outcomeIsUnknown, isFalse);
    });

    test('17 — cancelled at the terminal by the operator or cardholder', () async {
      host.answer(EcrMethods.sale, declinedPayload(responseCode: '17'));

      final EcrDeclined declined = await sale() as EcrDeclined;

      expect(declined.isCancelledAtTerminal, isTrue);
      expect(declined.outcomeIsUnknown, isFalse);
    });

    test('25 — the original was not found', () async {
      host.answer(EcrMethods.voidTransaction, declinedPayload(responseCode: '25'));

      final EcrResult result = await terminal.voidTransaction('215');

      expect((result as EcrDeclined).isOriginalNotFound, isTrue);
      expect(result.outcomeIsUnknown, isFalse);
    });

    test('91 — a decline whose outcome is UNKNOWN', () async {
      host.answer(
        EcrMethods.sale,
        declinedPayload(responseCode: '91', reason: 'Could not complete'),
      );

      final EcrResult result = await sale();

      // The one decline that is not a decision. A till that retries this
      // charges twice; it has to inquire instead.
      expect(result, isA<EcrDeclined>());
      expect(result.outcomeIsUnknown, isTrue);
    });

    test('a plain backend decline is a decision, and known', () async {
      host.answer(EcrMethods.sale, declinedPayload(responseCode: '51'));

      final EcrResult result = await sale();

      expect(result.outcomeIsUnknown, isFalse);
      expect((result as EcrDeclined).isTerminalBusy, isFalse);
    });
  });

  group('a partial approval is an approval', () {
    test('and carries what was asked for as well as what was taken', () async {
      host.answer(
        EcrMethods.sale,
        approvedPayload(
          amount: '0.500',
          partialApproval: true,
          requestedAmount: '2.000',
        ),
      );

      final EcrResult result = await sale();
      final EcrApproved approved = result as EcrApproved;

      expect(approved.partialApproval, isTrue);
      expect(approved.amount, '0.500');
      expect(approved.requestedAmount, '2.000');
      // Money moved. The goods go out once the remaining 1.500 is collected by
      // other means — but this is not a refusal.
      expect(approved.outcomeIsUnknown, isFalse);
    });
  });
}
