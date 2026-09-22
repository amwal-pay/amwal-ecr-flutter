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
