import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/src/dart_io/dart_io_amwal_ecr_platform.dart';
import 'package:amwal_ecr/src/dart_io/ecr_wire_readers.dart';
import 'package:amwal_ecr/src/platform/ecr_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EcrWireReaders', () {
    test('maps an approved envelope to EcrApproved', () {
      final EcrResult result = EcrWireReaders.toEcrResult(
        <String, Object?>{
          'success': true,
          'responseCode': '00',
          'message': 'Approved',
          'data': <String, Object?>{
            'merchantReference': 'ORDER-1',
            'amount': '1.234',
            'rrn': '123',
            'authCode': 'A1',
            'cardMask': '543173xxxx5785',
          },
        },
        merchantReference: 'ORDER-1',
        minorUnitDigits: 3,
      );

      expect(result, isA<EcrApproved>());
      final EcrApproved approved = result as EcrApproved;
      expect(approved.amount, '1.234');
      expect(approved.rrn, '123');
      expect(approved.maskedPan, '543173xxxx5785');
    });

    test('maps missing data on inquiry to NotFound', () {
      final EcrInquiry inquiry = EcrWireReaders.toInquiry(
        <String, Object?>{
          'success': false,
          'responseCode': '25',
          'message': 'Not found',
        },
        merchantReference: 'LOOKUP',
        minorUnitDigits: 3,
      );
      expect(inquiry, isA<EcrInquiryNotFound>());
    });

    test('NO_RESPONSE with inquire nextStep is EcrFailed timeout', () {
      final EcrResult result = EcrWireReaders.toEcrResult(
        <String, Object?>{
          'success': false,
          'responseCode': 'NO_RESPONSE',
          'message': 'timeout',
          'nextStep': 'INQUIRE_BY_MERCHANT_REFERENCE',
        },
        merchantReference: 'ORD-TIMEOUT-01',
        minorUnitDigits: 3,
      );

      expect(result, isA<EcrFailed>());
      final EcrFailed failed = result as EcrFailed;
      expect(failed.merchantReference, 'ORD-TIMEOUT-01');
      expect(failed.failure, isA<EcrTimeout>());
      expect(failed.failure.message, 'timeout');
      expect(failed.nextStep, EcrNextStep.inquireByMerchantReference);
    });

    test('ordinary decline without inquire nextStep stays Declined', () {
      final EcrResult result = EcrWireReaders.toEcrResult(
        <String, Object?>{
          'success': false,
          'responseCode': '51',
          'message': 'Declined',
          'nextStep': 'NONE',
        },
        merchantReference: 'ORD-DECLINE-01',
        minorUnitDigits: 3,
      );

      expect(result, isA<EcrDeclined>());
      final EcrDeclined declined = result as EcrDeclined;
      expect(declined.responseCode, '51');
      expect(declined.nextStep, EcrNextStep.none);
    });

    test('inquire nextStep without timeout wording is connectionLost', () {
      final EcrResult result = EcrWireReaders.toEcrResult(
        <String, Object?>{
          'success': false,
          'responseCode': '502',
          'message': 'Bad Gateway',
          'nextStep': 'INQUIRE_BY_MERCHANT_REFERENCE',
        },
        merchantReference: 'ORD-5XX-01',
        minorUnitDigits: 3,
      );

      expect(result, isA<EcrFailed>());
      final EcrFailed failed = result as EcrFailed;
      expect(failed.failure, isA<EcrConnectionLost>());
      expect(failed.failure.message, 'Bad Gateway');
    });

    test('reads a flat inquiry answer from the root', () {
      final EcrInquiry inquiry = EcrWireReaders.toInquiry(
        <String, Object?>{
          'success': true,
          'responseCode': '00',
          'merchantReference': 'ORIG-1',
          'systemTraceNr': '000013',
          'status': 'Approved',
          'amount': '1.000',
          'rrn': '999',
        },
        merchantReference: 'LOOKUP',
        minorUnitDigits: 3,
      );
      expect(inquiry, isA<EcrInquiryFound>());
      final EcrInquiryFound found = inquiry as EcrInquiryFound;
      expect(found.transaction.stan, '000013');
      expect(found.transaction.rrn, '999');
      expect(found.transaction.amount, '1.000');
    });

    test('nested data with markers wins; its reference resolves first', () {
      final EcrInquiry inquiry = EcrWireReaders.toInquiry(
        <String, Object?>{
          'success': true,
          'responseCode': '00',
          'data': <String, Object?>{
            'merchantReference': 'DATA-REF',
            'transactionId': 'T1',
            'status': 'Approved',
          },
        },
        merchantReference: 'LOOKUP',
        minorUnitDigits: 3,
      );
      expect(inquiry, isA<EcrInquiryFound>());
      expect((inquiry as EcrInquiryFound).merchantReference, 'DATA-REF');
    });

    test('correlation-only data is NotFound', () {
      final EcrInquiry inquiry = EcrWireReaders.toInquiry(
        <String, Object?>{
          'success': false,
          'responseCode': '25',
          'message': 'Not found',
          'data': <String, Object?>{'merchantReference': 'ORIG-1'},
        },
        merchantReference: 'LOOKUP',
        minorUnitDigits: 3,
      );
      expect(inquiry, isA<EcrInquiryNotFound>());
      expect((inquiry as EcrInquiryNotFound).merchantReference, 'ORIG-1');
    });

    test('majorUnits converts padded minor units', () {
      expect(EcrWireReaders.majorUnits('000000001234', 3), '1.234');
      expect(EcrWireReaders.majorUnits('', 3), '');
    });
  });

  group('DartIoAmwalEcrPlatform', () {
    test('USB cable is typed unsupported before anything is sent', () async {
      final DartIoAmwalEcrPlatform platform = DartIoAmwalEcrPlatform();
      final EcrResult result = await platform.sale(
        EcrRequest(
          operationId: 'op-1',
          host: '',
          serialNumber: 'P653200085189',
          transport: EcrTransport.usbCable,
          config: EcrConfig(),
          amount: EcrAmount.parse('1.000'),
        ),
      );
      expect(result, isA<EcrFailed>());
      expect((result as EcrFailed).failure, isA<EcrUnsupported>());
      expect(result.outcomeIsUnknown, isFalse);
    });
  });
}
