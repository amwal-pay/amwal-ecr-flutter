import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter_test/flutter_test.dart';

/// The codes the terminal generates itself, against `ecr-sdk/docs/protocol.md`
/// §6. The table there is the contract; this asserts the package agrees with
/// it, because the cost of disagreeing is a customer charged twice.
void main() {
  EcrDeclined declined(String code) => EcrDeclined(
        merchantReferenceId: 'ORD-1',
        responseCode: code,
        reason: '',
        raw: '{}',
      );

  group('terminal-generated codes', () {
    test('every code in the protocol table is known', () {
      // Missing one means it reads as a backend decline — a decision the
      // backend never made.
      for (final String code in <String>['12', '13', '17', '25', '63', '91', '94', '96']) {
        expect(
          EcrResponseCode.isTerminalGenerated(code),
          isTrue,
          reason: '$code is in protocol.md §6',
        );
      }
    });

    test('a backend code is not mistaken for a terminal one', () {
      for (final String code in <String>['00', '05', '51', '909']) {
        expect(EcrResponseCode.isTerminalGenerated(code), isFalse);
      }
    });
  });

  group('which declines leave the outcome unknown', () {
    test('91 does: the terminal says outright it cannot tell', () {
      expect(EcrResponseCode.leavesOutcomeUnknown(EcrResponseCode.indeterminate), isTrue);
      expect(declined('91').outcomeIsUnknown, isTrue);
    });

    test('94 does: the message was answered before, so it probably exists', () {
      // "94 is not a plain refusal: it means the terminal has answered this
      // exact message before, so the transaction it names probably exists.
      // Inquire rather than retry." — protocol.md §6. Reading it as a settled
      // refusal and sending the sale again is how the cardholder is charged
      // twice.
      expect(EcrResponseCode.leavesOutcomeUnknown(EcrResponseCode.alreadyAnswered), isTrue);
      expect(declined('94').outcomeIsUnknown, isTrue);
    });

    test('63 does not: nothing was attempted', () {
      // Unsigned, wrong key, or a clock too far out. A configuration fault, and
      // there is nothing to reconcile.
      expect(declined('63').outcomeIsUnknown, isFalse);
      expect(declined('63').isSecurityViolation, isTrue);
    });

    test('the refusals that happened before the backend do not', () {
      for (final String code in <String>['12', '13', '17', '25', '96']) {
        expect(declined(code).outcomeIsUnknown, isFalse, reason: code);
      }
    });
  });
}
