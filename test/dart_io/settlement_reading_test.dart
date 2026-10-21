import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/amwal_ecr_platform_interface.dart';
import 'package:amwal_ecr/src/dart_io/ecr_wire_readers.dart';
import 'package:flutter_test/flutter_test.dart';

/// A settlement answers in four shapes — closed with totals, nothing to close,
/// left open, refused before it started — and both ways a till reads it (the
/// terminal's JSON over the LAN, the Android host's map over the channel) have
/// to land on the same one.
void main() {
  group('EcrWireReaders.toSettlement', () {
    test('a closed batch reads its totals in major units', () {
      final EcrSettlement settlement = EcrWireReaders.toSettlement(
        <String, Object?>{
          'success': true,
          'responseCode': '00',
          'message': 'Settlement successful',
          'data': <String, Object?>{
            'merchantReference': 'SET01',
            'settlementStatus': 'SETTLED',
            'batchId': '00000007',
            'currency': 'OMR',
            'startTime': '20261020080000',
            'endTime': '20261020130509',
            'totalTransactions': 4,
            'netAmount': '000000012500',
            'totals': <String, Object?>{
              'SALE': <String, Object?>{'count': 3, 'amount': '000000014750'},
              'REFUND': <String, Object?>{'count': 1, 'amount': '000000002250'},
            },
          },
        },
        merchantReference: 'SET01',
        minorUnitDigits: 3,
      );

      final EcrSettlementSettled settled =
          settlement as EcrSettlementSettled;
      expect(settled.batchId, '00000007');
      expect(settled.totalTransactions, 4);
      expect(settled.netAmount, '12.500');
      expect(settled.totals['SALE'],
          const EcrSettlementTotal(count: 3, amount: '14.750'));
      expect(settled.totals['REFUND'],
          const EcrSettlementTotal(count: 1, amount: '2.250'));
      // A type the batch had none of is still there, as zero.
      expect(settled.totals['CAPTURE'],
          const EcrSettlementTotal(count: 0, amount: '0.000'));
      expect(settled.totals.keys, EcrSettlementSettled.totalTypes);
    });

    test('an empty batch is nothing to settle, not a failure', () {
      final EcrSettlement settlement = EcrWireReaders.toSettlement(
        <String, Object?>{
          'success': true,
          'responseCode': '00',
          'message': 'There are no transactions to settle',
          'data': <String, Object?>{'settlementStatus': 'NO_TRANSACTIONS'},
        },
        merchantReference: 'SET02',
        minorUnitDigits: 3,
      );

      expect(settlement, isA<EcrSettlementNothingToSettle>());
    });

    test('a mismatch leaves the batch open and says how many went up', () {
      final EcrSettlement settlement = EcrWireReaders.toSettlement(
        <String, Object?>{
          'success': false,
          'responseCode': '91',
          'message': 'Counts differ',
          'data': <String, Object?>{
            'settlementStatus': 'MISMATCH',
            'uploadedTransactions': 9,
          },
        },
        merchantReference: 'SET03',
        minorUnitDigits: 3,
      );

      final EcrSettlementNotSettled open =
          settlement as EcrSettlementNotSettled;
      expect(open.status, 'MISMATCH');
      expect(open.responseCode, '91');
      expect(open.uploadedTransactions, 9);
    });

    test('a busy terminal refuses with no settlement status', () {
      final EcrSettlement settlement = EcrWireReaders.toSettlement(
        <String, Object?>{
          'success': false,
          'responseCode': '96',
          'message': 'A transaction is already in progress on this terminal',
        },
        merchantReference: 'SET04',
        minorUnitDigits: 3,
      );

      final EcrSettlementNotSettled open =
          settlement as EcrSettlementNotSettled;
      expect(open.responseCode, '96');
      expect(open.status, '');
      expect(open.uploadedTransactions, isNull);
    });
  });

  group('EcrCodec.settlement', () {
    test('reads the map the Android host sends for a closed batch', () {
      final EcrSettlement settlement = EcrCodec.settlement(
        <Object?, Object?>{
          EcrResultKeys.outcome: EcrOutcomes.settled,
          EcrResultKeys.merchantReference: 'SET01',
          EcrSettlementKeys.batchId: '00000007',
          EcrSettlementKeys.currency: 'OMR',
          EcrSettlementKeys.startTime: '20261020080000',
          EcrSettlementKeys.endTime: '20261020130509',
          EcrSettlementKeys.totalTransactions: 4,
          EcrSettlementKeys.netAmount: '12.500',
          EcrSettlementKeys.totals: <Object?, Object?>{
            'SALE': <Object?, Object?>{
              EcrSettlementKeys.count: 3,
              EcrSettlementKeys.amount: '14.750',
            },
          },
          EcrResultKeys.raw: '{}',
        },
        operationId: 'op1',
      );

      final EcrSettlementSettled settled =
          settlement as EcrSettlementSettled;
      expect(settled.merchantReference, 'SET01');
      expect(settled.netAmount, '12.500');
      expect(settled.totals['SALE'],
          const EcrSettlementTotal(count: 3, amount: '14.750'));
      expect(settled.totals.keys, EcrSettlementSettled.totalTypes);
    });

    test('reads a batch left open', () {
      final EcrSettlement settlement = EcrCodec.settlement(
        <Object?, Object?>{
          EcrResultKeys.outcome: EcrOutcomes.declined,
          EcrResultKeys.merchantReference: 'SET03',
          EcrResultKeys.responseCode: '58',
          EcrResultKeys.responseMessage: 'The terminal session has expired',
          EcrSettlementKeys.status: 'SESSION_EXPIRED',
          EcrResultKeys.raw: '{}',
        },
        operationId: 'op2',
      );

      final EcrSettlementNotSettled open =
          settlement as EcrSettlementNotSettled;
      expect(open.status, 'SESSION_EXPIRED');
      expect(open.responseCode, '58');
      expect(open.uploadedTransactions, isNull);
    });

    test('reads nothing to settle', () {
      final EcrSettlement settlement = EcrCodec.settlement(
        <Object?, Object?>{
          EcrResultKeys.outcome: EcrOutcomes.nothingToSettle,
          EcrResultKeys.merchantReference: 'SET02',
          EcrSettlementKeys.message: 'There are no transactions to settle',
        },
        operationId: 'op3',
      );

      expect(settlement, isA<EcrSettlementNothingToSettle>());
    });
  });

  test('a Web Service terminal cannot be asked to settle', () {
    expect(EcrTransport.webService.supportsSettlement, isFalse);
    expect(EcrTransport.wifi.supportsSettlement, isTrue);
    expect(EcrTransport.usbCable.supportsSettlement, isTrue);
    expect(EcrTransport.appToApp.supportsSettlement, isTrue);
  });
}
