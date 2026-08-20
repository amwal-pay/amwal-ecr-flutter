import 'dart:convert';

import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/amwal_ecr_platform_interface.dart';
import 'package:amwal_ecr_example/data/terminal.dart';
import 'package:amwal_ecr_example/data/terminal_repository.dart';
import 'package:amwal_ecr_example/main.dart';
import 'package:amwal_ecr_example/ui/components/omr_symbol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The example till, driven without a terminal.
///
/// The tests follow the Android example's flow, in its order: validate, resolve
/// the terminal, probe it, then send. That order is the behaviour — a till that
/// sends before probing makes a cashier wait through a failure that could have
/// been an immediate answer — so it is asserted rather than assumed.
void main() {
  late FakeEcrPlatform platform;
  late TerminalRepository repository;

  const Terminal registered = Terminal(
    serialNumber: 'P653200085189',
    name: 'Counter 1',
    ipAddress: '192.168.1.50',
    port: 9100,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'terminals': <String>[jsonEncode(registered.toJson())],
    });
    platform = FakeEcrPlatform();
    AmwalEcrPlatform.instance = platform;
    repository = TerminalRepository();
  });

  tearDown(() => repository.dispose());

  Future<void> pumpTill(WidgetTester tester) async {
    await tester.pumpWidget(ExampleTillApp(repository: repository));
    await tester.pumpAndSettle();
  }

  Future<void> keyAmount(WidgetTester tester, String digits) async {
    await tester.enterText(find.byKey(const Key('amount')), digits);
    await tester.pumpAndSettle();
  }

  group('the order of the checks', () {
    testWidgets('the terminal is probed before anything is sent',
        (WidgetTester tester) async {
      platform.reachable = true;
      platform.result = _approved;

      await pumpTill(tester);
      await keyAmount(tester, '1234');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      // isReachable first, exactly as TransactionViewModel does it.
      expect(platform.calls, <String>['isReachable', 'sale']);
    });

    testWidgets('an unreachable terminal sends nothing at all',
        (WidgetTester tester) async {
      platform.reachable = false;

      await pumpTill(tester);
      await keyAmount(tester, '1234');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(platform.calls, <String>['isReachable']);
      expect(find.text('Not completed'), findsOneWidget);
      expect(
        find.textContaining('192.168.1.50:9100 is not reachable'),
        findsOneWidget,
      );
      // The advice the Android example gives, word for word — a terminal that
      // is not on its idle screen is the usual cause.
      expect(find.textContaining('sitting on its idle screen'), findsOneWidget);
    });

    testWidgets('an invalid form is not sent, and says which field',
        (WidgetTester tester) async {
      await pumpTill(tester);

      // No amount keyed.
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(platform.calls, isEmpty);
      expect(find.text('Required field'), findsOneWidget);
    });

    testWidgets('an amount below the minimum is refused before sending',
        (WidgetTester tester) async {
      await pumpTill(tester);
      await keyAmount(tester, '5'); // 0.005, under the 0.010 floor

      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(platform.calls, isEmpty);
      expect(find.textContaining('minimum amount allowed is'), findsOneWidget);
    });

    testWidgets('a void with no receipt number is not sent',
        (WidgetTester tester) async {
      await pumpTill(tester);
      await _chooseType(tester, 'Void');

      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(platform.calls, isEmpty);
      expect(
        find.text('Enter the receipt number of the transaction to act on'),
        findsOneWidget,
      );
    });
  });

  group('the amount field', () {
    testWidgets('renders keyed digits with the point drawn in',
        (WidgetTester tester) async {
      await pumpTill(tester);
      await keyAmount(tester, '1234');

      // The operator keys 1234 and the field shows 1.234; there is no decimal
      // key, so two points cannot be keyed.
      expect(find.text('1.234'), findsOneWidget);
    });

    testWidgets('sends the amount in major units', (WidgetTester tester) async {
      platform.result = _approved;

      await pumpTill(tester);
      await keyAmount(tester, '1234');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(platform.lastAmount.toString(), '1.234');
    });

    testWidgets('is disabled for an operation that carries no amount',
        (WidgetTester tester) async {
      await pumpTill(tester);
      await _chooseType(tester, 'Void');

      final TextField amount =
          tester.widget<TextField>(find.byKey(const Key('amount')));
      expect(amount.enabled, isFalse);
      expect(
        find.text("Uses the original transaction's amount"),
        findsOneWidget,
      );
    });
  });

  group('outcomes', () {
    testWidgets('an approval shows the amount and the card',
        (WidgetTester tester) async {
      platform.result = _approved;

      await pumpTill(tester);
      await keyAmount(tester, '1234');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(find.text('Approved'), findsOneWidget);
      // By key: the amount reads the same as the digits still in the form
      // behind the dialog, and the currency now sits beside it as the symbol
      // the terminal draws rather than as the letters "OMR".
      expect(
        tester.widget<Text>(find.byKey(const Key('resultAmount'))).data,
        '1.234',
      );
      expect(find.byType(OmrSymbol), findsOneWidget);
      expect(find.text('543173xxxx5785'), findsOneWidget);
    });

    testWidgets('a partial approval names the difference to collect',
        (WidgetTester tester) async {
      platform.result = const EcrApproved(
        merchantReferenceId: 'A1',
        amount: '0.500',
        responseCode: '00',
        rrn: 'R1',
        authCode: 'A1',
        maskedPan: '',
        partialApproval: true,
        requestedAmount: '2.000',
        raw: '{}',
      );

      await pumpTill(tester);
      await keyAmount(tester, '2000');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(find.text('Partially approved'), findsOneWidget);
      expect(
        find.textContaining('Only 0.500 of 2.000 was approved'),
        findsOneWidget,
      );
    });

    testWidgets('a decline shows the terminal\'s own reason',
        (WidgetTester tester) async {
      // Response code 96: the terminal already has a transaction running. The
      // till shows what the terminal said and nothing more — there is no retry
      // to offer, because nothing was attempted.
      platform.result = const EcrDeclined(
        merchantReferenceId: 'A1',
        responseCode: '96',
        reason: 'A transaction is already in progress on this terminal',
        raw: '{}',
      );

      await pumpTill(tester);
      await keyAmount(tester, '1234');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(find.text('Declined'), findsOneWidget);
      expect(
        find.text('A transaction is already in progress on this terminal'),
        findsOneWidget,
      );
    });

    testWidgets('a lost answer reads as "Outcome unknown", not as a decline',
        (WidgetTester tester) async {
      // The request went out and nothing came back, so the sale may well have
      // completed. Calling that a decline is how a cardholder gets charged
      // twice.
      platform.result = const EcrFailed(
        merchantReferenceId: 'A1',
        failure: EcrTimeout('The terminal did not answer within 120s.'),
      );

      await pumpTill(tester);
      await keyAmount(tester, '1234');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(find.text('Outcome unknown'), findsOneWidget);
      expect(find.text('Declined'), findsNothing);
      expect(find.text('Not completed'), findsNothing);
      // The only action offered, and the reference it will ask about.
      expect(find.byKey(const Key('inquireByReference')), findsOneWidget);
      expect(find.text('A1'), findsOneWidget);
    });

    testWidgets('an unreachable terminal reads as "Not completed"',
        (WidgetTester tester) async {
      // Nothing was ever sent, so there is nothing to ask about and no
      // reference to ask with.
      platform.reachable = false;

      await pumpTill(tester);
      await keyAmount(tester, '1234');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(find.text('Not completed'), findsOneWidget);
      expect(find.text('Outcome unknown'), findsNothing);
      expect(find.byKey(const Key('inquireByReference')), findsNothing);
    });

    testWidgets('a lost answer the SDK already recovered shows what happened',
        (WidgetTester tester) async {
      // The SDK follows a lost answer with an inquiry of its own. Showing
      // "unknown" anyway, and asking the operator to repeat a question already
      // answered, would waste the recovery entirely.
      platform.result = EcrFailed(
        merchantReferenceId: 'A1',
        failure: const EcrTimeout('The terminal did not answer within 120s.'),
        recovered: _found('Approved'),
      );

      await pumpTill(tester);
      await keyAmount(tester, '1234');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Outcome unknown'), findsNothing);
      expect(find.byKey(const Key('inquireByReference')), findsNothing);
    });

    testWidgets('a receipt after a lookup by reference asks by the found stan',
        (WidgetTester tester) async {
      // The reason for looking up by reference is that there is no receipt
      // number to type. It comes back in what the inquiry found, and that is
      // what the receipt has to be asked for by.
      platform.inquiry = _found('Approved');
      platform.nextReceipt = const EcrReceiptReady(
        merchantReferenceId: 'A1',
        url: 'https://receipts.example/1',
        raw: '{}',
      );

      await pumpTill(tester);
      await _chooseType(tester, 'Inquiry');
      await tester.tap(find.byKey(const Key('lookUpByReference')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('merchantReference')),
        'ORD-88231',
      );
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('qrReceipt')));
      await tester.pumpAndSettle();

      expect(platform.lastReceiptNumber, _found('Approved').transaction.stan);
      expect(find.byKey(const Key('receiptQr')), findsOneWidget);
    });

    testWidgets('an inquiry can be keyed by reference instead of receipt number',
        (WidgetTester tester) async {
      platform.inquiry = _found('Approved');

      await pumpTill(tester);
      await _chooseType(tester, 'Inquiry');

      // The switch is offered for an inquiry, and only for an inquiry.
      expect(find.byKey(const Key('lookUpByReference')), findsOneWidget);
      expect(find.byKey(const Key('receiptNumber')), findsOneWidget);
      expect(find.byKey(const Key('merchantReference')), findsNothing);

      await tester.tap(find.byKey(const Key('lookUpByReference')));
      await tester.pumpAndSettle();

      // The receipt number gives way to the reference, and the date goes with
      // it: a reference is unique in its own right.
      expect(find.byKey(const Key('merchantReference')), findsOneWidget);
      expect(find.byKey(const Key('receiptNumber')), findsNothing);
      expect(find.byKey(const Key('originalDate')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('merchantReference')),
        'ORD-88231',
      );
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(platform.calls, <String>['isReachable', 'inquireByReference']);
      expect(platform.lastInquiredReference, 'ORD-88231');
    });

    testWidgets('an inquiry by reference with no reference is not sent',
        (WidgetTester tester) async {
      await pumpTill(tester);
      await _chooseType(tester, 'Inquiry');
      await tester.tap(find.byKey(const Key('lookUpByReference')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(platform.calls, isEmpty);
      expect(
        find.text('Enter the reference the transaction was sent with'),
        findsOneWidget,
      );
    });

    testWidgets('only an inquiry is offered the reference switch',
        (WidgetTester tester) async {
      await pumpTill(tester);

      for (final String type in <String>['Sale', 'Void', 'Refund']) {
        await _chooseType(tester, type);
        expect(
          find.byKey(const Key('lookUpByReference')),
          findsNothing,
          reason: '$type must not offer a lookup by reference',
        );
      }
    });

    testWidgets('inquiring by reference looks the transaction up by it',
        (WidgetTester tester) async {
      platform.result = const EcrFailed(
        merchantReferenceId: 'A1',
        failure: EcrTimeout('The terminal did not answer within 120s.'),
      );
      platform.inquiry = _found('Approved');

      await pumpTill(tester);
      await keyAmount(tester, '1234');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inquireByReference')));
      await tester.pumpAndSettle();

      // Asked by reference, which is the only identifier a till that lost the
      // answer still holds — a receipt number arrives *in* the answer.
      expect(platform.lastInquiredReference, 'A1');
      expect(find.text('Approved'), findsOneWidget);
    });

    testWidgets('a void hides the auth code, which it does not have',
        (WidgetTester tester) async {
      platform.result = _approved;

      await pumpTill(tester);
      await _chooseType(tester, 'Void');
      await tester.enterText(find.byKey(const Key('receiptNumber')), '215');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      // A void reverses an authorisation rather than obtaining one; printing
      // the placeholder would read as an approval that never took place.
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Auth code'), findsNothing);
    });
  });

  group('inquiry', () {
    testWidgets('shows the transaction\'s own status, not the lookup\'s',
        (WidgetTester tester) async {
      platform.inquiry = _found('Declined');

      await pumpTill(tester);
      await _chooseType(tester, 'Inquiry');
      await tester.enterText(find.byKey(const Key('receiptNumber')), '208');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      // The lookup succeeded. The transaction it found did not.
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('000208'), findsOneWidget);
    });

    testWidgets('offers the receipt from the result it belongs to',
        (WidgetTester tester) async {
      platform.inquiry = _found('Approved');
      platform.nextReceipt = const EcrReceiptReady(
        merchantReferenceId: 'A1',
        url: 'https://test.amwalpg.com/r/1',
        raw: '{}',
      );

      await pumpTill(tester);
      await _chooseType(tester, 'Inquiry');
      await tester.enterText(find.byKey(const Key('receiptNumber')), '208');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('qrReceipt')));
      await tester.pumpAndSettle();

      // The transaction is named by the inquiry's own request rather than
      // re-keyed, so the receipt asks about the same receipt number.
      expect(platform.calls, <String>['isReachable', 'inquire', 'receipt']);
      expect(find.byKey(const Key('receiptQr')), findsOneWidget);
    });

    testWidgets('a lookup that found nothing is not an error',
        (WidgetTester tester) async {
      platform.inquiry = const EcrInquiryNotFound(
        merchantReferenceId: 'A1',
        reason: 'No transactions found for the provided STAN and Terminal',
        raw: '{}',
      );

      await pumpTill(tester);
      await _chooseType(tester, 'Inquiry');
      await tester.enterText(find.byKey(const Key('receiptNumber')), '208');
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      expect(find.text('Not found'), findsOneWidget);
    });
  });

  group('terminals', () {
    testWidgets('with none registered, nothing can be started',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final TerminalRepository empty = TerminalRepository();
      addTearDown(empty.dispose);

      await tester.pumpWidget(ExampleTillApp(repository: empty));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('noTerminals')), findsOneWidget);
      final FilledButton start =
          tester.widget<FilledButton>(find.byKey(const Key('start')));
      expect(start.onPressed, isNull);
    });

    testWidgets('a registered terminal is offered by name and serial',
        (WidgetTester tester) async {
      await pumpTill(tester);

      expect(find.text('Counter 1 (P653200085189)'), findsOneWidget);
    });

    testWidgets('the terminals screen lists what is registered',
        (WidgetTester tester) async {
      await pumpTill(tester);

      await tester.tap(find.byKey(const Key('terminals')));
      await tester.pumpAndSettle();

      expect(find.text('Counter 1'), findsOneWidget);
      expect(find.textContaining('192.168.1.50:9100'), findsOneWidget);
    });

    testWidgets('a terminal is added with name, serial, address and port',
        (WidgetTester tester) async {
      await pumpTill(tester);
      await tester.tap(find.byKey(const Key('terminals')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('addTerminal')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('terminalName')), 'Counter 2');
      await tester.enterText(
        find.byKey(const Key('serialNumber')),
        'P653200085190',
      );
      await tester.enterText(find.byKey(const Key('ipAddress')), '192.168.1.51');
      await tester.enterText(find.byKey(const Key('port')), '9100');
      await tester.tap(find.byKey(const Key('saveTerminal')));
      await tester.pumpAndSettle();

      expect(find.text('Counter 2'), findsOneWidget);
    });

    testWidgets('a bad address is refused with the same rules as Android',
        (WidgetTester tester) async {
      await pumpTill(tester);
      await tester.tap(find.byKey(const Key('terminals')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addTerminal')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('terminalName')), 'Counter 2');
      await tester.enterText(find.byKey(const Key('serialNumber')), 'X1');
      await tester.enterText(find.byKey(const Key('ipAddress')), '999.1.1.1');
      await tester.enterText(find.byKey(const Key('port')), '70000');
      await tester.tap(find.byKey(const Key('saveTerminal')));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter a valid IPv4 address, for example 192.168.1.50'),
        findsOneWidget,
      );
      expect(find.text('Port must be between 1 and 65535'), findsOneWidget);
    });

    testWidgets('a serial number already registered is refused',
        (WidgetTester tester) async {
      await pumpTill(tester);
      await tester.tap(find.byKey(const Key('terminals')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addTerminal')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('terminalName')), 'Duplicate');
      await tester.enterText(
        find.byKey(const Key('serialNumber')),
        'P653200085189',
      );
      await tester.enterText(find.byKey(const Key('ipAddress')), '192.168.1.52');
      await tester.enterText(find.byKey(const Key('port')), '9100');
      await tester.tap(find.byKey(const Key('saveTerminal')));
      await tester.pumpAndSettle();

      // Two entries for one terminal, or one pointing at the wrong address, is
      // worse than a save that did not happen.
      expect(
        find.textContaining('is already registered'),
        findsOneWidget,
      );
    });
  });
}

const EcrApproved _approved = EcrApproved(
  merchantReferenceId: 'A1B2C3D4E5F6',
  amount: '1.234',
  responseCode: '00',
  rrn: '622113155340',
  authCode: '517842',
  maskedPan: '543173xxxx5785',
  partialApproval: false,
  requestedAmount: '',
  raw: '{"approved":true}',
);

EcrInquiryFound _found(String status) => EcrInquiryFound(
      merchantReferenceId: 'B1',
      transaction: EcrTransaction(
        transactionId: 'e970c800',
        stan: '000208',
        type: 'Purchase',
        status: status,
        amount: '0.258',
        totalAmount: '0.258',
        currency: 'OMR',
        transactionTime: '2026-08-09T16:58:16',
        maskedPan: '543173******5785',
        cardHolderName: '',
        rrn: 'R1',
        authCode: '',
        batchId: '00000003',
        terminalId: '31629',
        isRefunded: false,
        canVoid: true,
        canRefund: true,
      ),
      raw: '{}',
    );

/// Picks a transaction type from the dropdown.
Future<void> _chooseType(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('transactionType')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// A terminal that answers whatever the test tells it to.
final class FakeEcrPlatform extends AmwalEcrPlatform {
  bool reachable = true;

  EcrResult result = const EcrFailed(
    merchantReferenceId: '',
    failure: EcrUnreachable('nothing configured'),
  );

  EcrInquiry inquiry = const EcrInquiryNotFound(
    merchantReferenceId: '',
    reason: 'nothing configured',
    raw: '{}',
  );

  EcrReceipt nextReceipt = const EcrReceiptUnavailable(
    merchantReferenceId: '',
    reason: 'nothing configured',
    raw: '{}',
  );

  final List<String> calls = <String>[];

  /// What the last money-moving call carried, in major units.
  Object? lastAmount;

  /// The reference the last inquiry-by-reference asked about.
  String? lastInquiredReference;

  /// The receipt number the last receipt request asked by.
  String? lastReceiptNumber;

  @override
  Future<bool> isReachable(EcrRequest request) async {
    calls.add('isReachable');
    return reachable;
  }

  @override
  Future<EcrResult> sale(EcrRequest request) async {
    calls.add('sale');
    lastAmount = request.amount;
    return result;
  }

  @override
  Future<EcrResult> voidTransaction(EcrRequest request) async {
    calls.add('void');
    return result;
  }

  @override
  Future<EcrResult> refund(EcrRequest request) async {
    calls.add('refund');
    lastAmount = request.amount;
    return result;
  }

  @override
  Future<EcrInquiry> inquire(EcrRequest request) async {
    calls.add('inquire');
    return inquiry;
  }

  @override
  Future<EcrInquiry> inquireByReference(EcrRequest request) async {
    calls.add('inquireByReference');
    lastInquiredReference = request.originalMerchantReference;
    return inquiry;
  }

  @override
  Future<EcrReceipt> receipt(EcrRequest request) async {
    calls.add('receipt');
    lastReceiptNumber = request.receiptNumber;
    return nextReceipt;
  }

  @override
  Future<bool> cancel(String operationId) async => false;
}
