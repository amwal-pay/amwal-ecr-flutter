import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/amwal_ecr_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading what the host sends back, field for field.
///
/// The maps here are what the Kotlin and Swift `EcrMapping`s produce from the
/// terminal payloads in `ecr-sdk/docs/protocol.md`, so a change on either host
/// that drops a field or renames one shows up as a failure here rather than as
/// a blank line on a receipt.
void main() {
  group('an inquiry that found the transaction', () {
    /// The real answer from the protocol document, as the host maps it.
    Map<String, Object?> foundPayload() => <String, Object?>{
          EcrResultKeys.outcome: EcrOutcomes.found,
          EcrResultKeys.merchantReferenceId: 'D4E5F6A1B2C3',
          EcrResultKeys.raw: '{"approved":true}',
          EcrResultKeys.transaction: <String, Object?>{
            EcrTransactionKeys.transactionId:
                'e970c800-93f1-11f1-9485-e7dd858253ff',
            EcrTransactionKeys.stan: '000208',
            EcrTransactionKeys.type: 'Purchase',
            EcrTransactionKeys.status: 'Approved',
            EcrTransactionKeys.amount: '0.258',
            EcrTransactionKeys.totalAmount: '0.258',
            EcrTransactionKeys.currency: 'OMR',
            EcrTransactionKeys.transactionTime: '2026-08-09T16:58:16.804271',
            EcrTransactionKeys.maskedPan: '543173******5785',
            EcrTransactionKeys.cardHolderName: '',
            EcrTransactionKeys.rrn: '7862802964726844904806',
            EcrTransactionKeys.authCode: '',
            EcrTransactionKeys.batchId: '00000003',
            EcrTransactionKeys.terminalId: '31629',
            EcrTransactionKeys.isRefunded: false,
            EcrTransactionKeys.canVoid: true,
            EcrTransactionKeys.canRefund: true,
          },
        };

    test('carries every field the backend recorded', () {
      final EcrInquiry inquiry =
          EcrCodec.inquiry(foundPayload(), operationId: 'op-1');

      final EcrTransaction transaction =
          (inquiry as EcrInquiryFound).transaction;

      expect(inquiry.merchantReferenceId, 'D4E5F6A1B2C3');
      expect(transaction.transactionId, 'e970c800-93f1-11f1-9485-e7dd858253ff');
      expect(transaction.stan, '000208');
      expect(transaction.type, 'Purchase');
      expect(transaction.status, 'Approved');
      // Major units: the backend's own record, not the wire's minor-unit form.
      expect(transaction.amount, '0.258');
      expect(transaction.totalAmount, '0.258');
      expect(transaction.currency, 'OMR');
      expect(transaction.transactionTime, '2026-08-09T16:58:16.804271');
      expect(transaction.maskedPan, '543173******5785');
      expect(transaction.rrn, '7862802964726844904806');
      expect(transaction.batchId, '00000003');
      expect(transaction.terminalId, '31629');
      expect(transaction.isRefunded, isFalse);
      // Already has the void window and the backend's rules applied, so a till
      // can enable its buttons from these rather than guessing.
      expect(transaction.canVoid, isTrue);
      expect(transaction.canRefund, isTrue);
    });

    test('found is not the same as paid', () {
      final EcrInquiryFound found = EcrCodec.inquiry(
        foundPayload()
          ..[EcrResultKeys.transaction] = <String, Object?>{
            ...foundPayload()[EcrResultKeys.transaction]!
                as Map<String, Object?>,
            EcrTransactionKeys.status: 'Declined',
          },
        operationId: 'op-1',
      ) as EcrInquiryFound;

      // The inquiry succeeded. The transaction it describes did not.
      expect(found.transaction.status, 'Declined');
    });

    test('a terminalId that arrives as a number is read as text', () {
      // The backend sends it as a JSON number; one codec keeps it a number and
      // the other stringifies it. Either way it is an identifier, not a
      // quantity, and a till comparing it to a string must not fail.
      final Map<String, Object?> payload = foundPayload();
      (payload[EcrResultKeys.transaction]! as Map<String, Object?>)[
          EcrTransactionKeys.terminalId] = 31629;

      final EcrInquiryFound found =
          EcrCodec.inquiry(payload, operationId: 'op-1') as EcrInquiryFound;

      expect(found.transaction.terminalId, '31629');
    });

    test('nulls read as empty, never as the text "null"', () {
      final Map<String, Object?> payload = foundPayload();
      (payload[EcrResultKeys.transaction]! as Map<String, Object?>)
        ..[EcrTransactionKeys.cardHolderName] = null
        ..[EcrTransactionKeys.authCode] = null;

      final EcrInquiryFound found =
          EcrCodec.inquiry(payload, operationId: 'op-1') as EcrInquiryFound;

      expect(found.transaction.cardHolderName, '');
      expect(found.transaction.authCode, '');
    });

    test('a flag sent as text is still a flag', () {
      final Map<String, Object?> payload = foundPayload();
      (payload[EcrResultKeys.transaction]! as Map<String, Object?>)
        ..[EcrTransactionKeys.canVoid] = 'true'
        ..[EcrTransactionKeys.canRefund] = 'false';

      final EcrInquiryFound found =
          EcrCodec.inquiry(payload, operationId: 'op-1') as EcrInquiryFound;

      expect(found.transaction.canVoid, isTrue);
      expect(found.transaction.canRefund, isFalse);
    });

    test('"found" with no transaction is a failure, not a record of blanks', () {
      final Map<String, Object?> payload = foundPayload()
        ..remove(EcrResultKeys.transaction);

      final EcrInquiry inquiry =
          EcrCodec.inquiry(payload, operationId: 'op-1');

      // Handing back seventeen empty strings would look like a real answer.
      expect(inquiry, isA<EcrInquiryFailed>());
      expect((inquiry as EcrInquiryFailed).failure, isA<EcrMalformed>());
    });
  });

  group('an inquiry that found nothing', () {
    test('carries the backend\'s own words', () {
      final EcrInquiry inquiry = EcrCodec.inquiry(
        <String, Object?>{
          EcrResultKeys.outcome: EcrOutcomes.notFound,
          EcrResultKeys.merchantReferenceId: 'D4E5F6A1B2C3',
          EcrResultKeys.responseMessage:
              'No transactions found for the provided STAN and Terminal',
          EcrResultKeys.raw: '{"approved":false}',
        },
        operationId: 'op-1',
      );

      expect(inquiry, isA<EcrInquiryNotFound>());
      expect(
        (inquiry as EcrInquiryNotFound).reason,
        'No transactions found for the provided STAN and Terminal',
      );
      expect(inquiry.raw, '{"approved":false}');
    });
  });

  group('an inquiry that could not be made', () {
    test('is a failure, and one that is safe to retry', () {
      final EcrInquiry inquiry = EcrCodec.inquiry(
        <String, Object?>{
          EcrResultKeys.outcome: EcrOutcomes.failed,
          EcrResultKeys.merchantReferenceId: '',
          EcrResultKeys.failure: <String, Object?>{
            EcrFailureKeys.kind: EcrFailureKinds.unreachable,
            EcrFailureKeys.message: 'no route to 192.168.1.50:9100',
          },
        },
        operationId: 'op-1',
      );

      expect(inquiry, isA<EcrInquiryFailed>());
      final EcrFailure failure = (inquiry as EcrInquiryFailed).failure;
      expect(failure, isA<EcrUnreachable>());
      // An inquiry changes nothing, so nothing is left in doubt by one failing.
      expect(failure.outcomeIsUnknown, isFalse);
    });

    test('a payload that is not a map at all is still an inquiry failure', () {
      final EcrInquiry inquiry = EcrCodec.inquiry('nonsense', operationId: 'op');

      expect(inquiry, isA<EcrInquiryFailed>());
      expect((inquiry as EcrInquiryFailed).failure, isA<EcrMalformed>());
    });
  });

  group('a receipt', () {
    test('ready carries the URL to put in a QR code', () {
      final EcrReceipt receipt = EcrCodec.receipt(
        <String, Object?>{
          EcrResultKeys.outcome: EcrOutcomes.ready,
          EcrResultKeys.merchantReferenceId: 'E5F6A1B2C3D4',
          EcrResultKeys.url:
              'https://test.amwalpg.com:25446/Transaction/DownloadReceipt?transactionId=318873a0',
          EcrResultKeys.raw: '{}',
        },
        operationId: 'op-1',
      );

      expect(receipt, isA<EcrReceiptReady>());
      expect(
        (receipt as EcrReceiptReady).url,
        startsWith('https://test.amwalpg.com'),
      );
    });

    test('"ready" with an empty URL is not a receipt', () {
      // An empty receiptUrl means no receipt, whatever the response code says.
      final EcrReceipt receipt = EcrCodec.receipt(
        <String, Object?>{
          EcrResultKeys.outcome: EcrOutcomes.ready,
          EcrResultKeys.merchantReferenceId: 'E5F6A1B2C3D4',
          EcrResultKeys.url: '',
          EcrResultKeys.responseMessage: 'Receipt ready',
          EcrResultKeys.raw: '{}',
        },
        operationId: 'op-1',
      );

      expect(receipt, isA<EcrReceiptUnavailable>());
    });

    test('unavailable carries why, and is safe to ask again later', () {
      final EcrReceipt receipt = EcrCodec.receipt(
        <String, Object?>{
          EcrResultKeys.outcome: EcrOutcomes.unavailable,
          EcrResultKeys.merchantReferenceId: 'E5F6A1B2C3D4',
          EcrResultKeys.responseMessage: 'Transaction not found',
          EcrResultKeys.raw: '{}',
        },
        operationId: 'op-1',
      );

      expect(
        (receipt as EcrReceiptUnavailable).reason,
        'Transaction not found',
      );
    });

    test('a failure is its own type, not a sale\'s', () {
      final EcrReceipt receipt = EcrCodec.receipt(
        <String, Object?>{
          EcrResultKeys.outcome: EcrOutcomes.failed,
          EcrResultKeys.merchantReferenceId: '',
          EcrResultKeys.failure: <String, Object?>{
            EcrFailureKeys.kind: EcrFailureKinds.timeout,
            EcrFailureKeys.message: 'no answer',
          },
        },
        operationId: 'op-1',
      );

      expect(receipt, isA<EcrReceiptFailed>());
      expect((receipt as EcrReceiptFailed).failure, isA<EcrTimeout>());
    });
  });

  group('the failure sub-map on its own', () {
    test('maps each kind to its type', () {
      final Map<String, Type> expected = <String, Type>{
        EcrFailureKinds.unreachable: EcrUnreachable,
        EcrFailureKinds.timeout: EcrTimeout,
        EcrFailureKinds.malformed: EcrMalformed,
        EcrFailureKinds.connectionLost: EcrConnectionLost,
        EcrFailureKinds.cancelled: EcrCancelled,
        EcrFailureKinds.unsupported: EcrUnsupported,
      };

      expected.forEach((String kind, Type type) {
        final EcrFailure failure = EcrCodec.failure(<String, Object?>{
          EcrFailureKeys.kind: kind,
          EcrFailureKeys.message: 'because',
        });
        expect(failure.runtimeType, type, reason: kind);
      });
    });

    test('every kind in the contract is mapped — none falls through', () {
      for (final String kind in EcrFailureKinds.all) {
        final EcrFailure failure = EcrCodec.failure(<String, Object?>{
          EcrFailureKeys.kind: kind,
          EcrFailureKeys.message: 'because',
        });
        // A kind that fell through would come back as EcrMalformed carrying the
        // "this version does not know" wording.
        expect(
          failure.message,
          isNot(contains('does not know')),
          reason: '"$kind" is in the contract but is not mapped',
        );
      }
    });
  });
}
