import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr_example/print/receipt_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromOperation maps approved fields into layout slots', () {
    final ReceiptLayout layout = ReceiptLayout.fromOperation(
      const EcrApproved(
        merchantReference: 'ORD-42',
        amount: '10.500',
        responseCode: '00',
        rrn: '622113155340',
        authCode: 'A1B2C3',
        maskedPan: '411111******1111',
        partialApproval: false,
        requestedAmount: '',
        raw: '',
      ),
      EcrTransactionType.sale,
      now: DateTime(2026, 10, 5, 14, 30),
    );

    expect(layout.businessName, 'Amwal Pay');
    expect(layout.orderBox, 'الطلب: Order - ORD-42');
    expect(layout.orderType, 'Sale');
    expect(layout.grandTotalValue, 'OMR 10.500');
    expect(layout.items.single.$2, 'Sale - SALE');
    expect(layout.items.single.$3, '10.500');

    final Map<String, String> meta = Map<String, String>.fromEntries(
      layout.meta.map(((String, String) e) => MapEntry<String, String>(e.$1, e.$2)),
    );
    expect(meta['Invoice - رقم الفاتورة'], 'ORD-42');
    expect(meta['Auth - رمز التفويض'], 'A1B2C3');
    expect(meta['RRN - رقم المرجع'], '622113155340');
    expect(meta['Card - البطاقة'], '411111******1111');
    expect(meta['Code - رمز الاستجابة'], '00');
    expect(meta['Paid Status - حالة الدفع'], 'Paid - مدفوع');
    expect(meta['Order Date - تاريخ الطلب'], '2026/10/05');
    expect(meta['Order Time - وقت الطلب'], '2:30 PM');
    expect(layout.footerThanks, 'Thank you - شكرا لكم');
  });

  test('void omits auth from meta', () {
    final ReceiptLayout layout = ReceiptLayout.fromOperation(
      const EcrApproved(
        merchantReference: 'V-1',
        amount: '10.500',
        responseCode: '00',
        rrn: '1',
        authCode: '000000',
        maskedPan: '',
        partialApproval: false,
        requestedAmount: '',
        raw: '',
      ),
      EcrTransactionType.voidTransaction,
      now: DateTime(2026, 1, 1),
    );

    expect(
      layout.meta.any(((String, String) e) => e.$1.startsWith('Auth')),
      isFalse,
    );
  });
}
