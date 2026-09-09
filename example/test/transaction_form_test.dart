import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr_example/ui/transaction/transaction_form.dart';
import 'package:amwal_ecr_example/ui/transaction/transaction_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransactionFormState sale merchant reference', () {
    test('blank reference is allowed and sent as empty', () {
      final (TransactionFormState form, TransactionRequest? request) =
          TransactionFormState(
        amountDigits: '1234',
        merchantReference: '   ',
      ).validated('TW1');

      expect(form.errors.merchantReference, isNull);
      expect(request?.merchantReference, '');
    });

    test('provided reference is trimmed onto the request', () {
      final (TransactionFormState form, TransactionRequest? request) =
          TransactionFormState(
        amountDigits: '1234',
        merchantReference: '  ORD-88231  ',
      ).validated('TW1');

      expect(form.errors.merchantReference, isNull);
      expect(request?.merchantReference, 'ORD-88231');
    });

    test('invalid reference is refused before sending', () {
      final (TransactionFormState form, TransactionRequest? request) =
          TransactionFormState(
        merchantReference: 'bad ref',
      ).validated('TW1');

      expect(form.errors.merchantReference, isNotNull);
      expect(request, isNull);
    });

    test('merchant reference field is sale-only', () {
      expect(TransactionFormState().showMerchantReference, isTrue);
      expect(
        TransactionFormState(type: EcrTransactionType.voidTransaction)
            .showMerchantReference,
        isFalse,
      );
    });

    test('inquiry by reference copies input onto merchantReference', () {
      final (TransactionFormState form, TransactionRequest? request) =
          TransactionFormState(
        type: EcrTransactionType.inquiry,
        lookUpByReference: true,
        originalReference: 'ORD-88231',
      ).validated('TW1');

      expect(form.errors.any, isFalse);
      expect(request?.originalReference, 'ORD-88231');
      expect(request?.merchantReference, 'ORD-88231');
    });
  });
}
