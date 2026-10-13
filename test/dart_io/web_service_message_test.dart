import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/src/dart_io/ecr_environment_urls.dart';
import 'package:amwal_ecr/src/dart_io/web_service/ecr_web_service_http.dart';
import 'package:amwal_ecr/src/dart_io/web_service/ecr_web_service_message.dart';
import 'package:amwal_ecr/src/dart_io/web_service/web_service_ecr_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EcrWebServiceMessage', () {
    test('inquiry by STAN leaves originalMerchantReference empty', () {
      final (String, Map<String, Object?>) built = EcrWebServiceMessage.build(
        type: EcrTransactionType.inquiry,
        merchantId: 8899,
        terminalId: 999,
        terminalSerial: 'QQW',
        secureHashKey: '',
        stan: '13',
        originalTransactionDate: '20260826',
        merchantReference: '0B574EB48120',
        transactionDateTime: '20260826120654',
      );

      expect(built.$1, '0B574EB48120');
      expect(built.$2['stan'], '000013');
      expect(built.$2['originalMerchantReference'], '');
      expect(built.$2['originalTerminalId'], 999);
      expect(built.$2['requestDateTime'], '20260826120654');
      expect(built.$2['transactionDateTime'], '20260826120654');
    });

    test('inquiry by reference sets originalMerchantReference', () {
      final (String, Map<String, Object?>) built = EcrWebServiceMessage.build(
        type: EcrTransactionType.inquiry,
        merchantId: 8899,
        terminalId: 999,
        terminalSerial: 'QQW',
        secureHashKey: '',
        stan: '',
        originalTransactionDate: '20260826',
        originalMerchantReference: 'ORD-88231ABC',
        merchantReference: 'INQ-NEW-REF01',
        transactionDateTime: '20260826120654',
      );

      expect(built.$1, 'INQ-NEW-REF01');
      expect(built.$2['stan'], '');
      expect(built.$2['originalMerchantReference'], 'ORD-88231ABC');
      expect(built.$2['originalTerminalId'], 999);
      expect(built.$2['requestDateTime'], '20260826120654');
    });

    test('void carries originalMerchantReference and originalTerminalId', () {
      final (String, Map<String, Object?>) built = EcrWebServiceMessage.build(
        type: EcrTransactionType.voidTransaction,
        merchantId: 8899,
        terminalId: 999,
        terminalSerial: 'QQW',
        secureHashKey: '',
        stan: '8',
        merchantReference: '77619797A075',
        transactionDateTime: '20260826120107',
      );

      expect(built.$2['stan'], '000008');
      expect(built.$2['originalMerchantReference'], '77619797A075');
      expect(built.$2['originalTerminalId'], 999);
      expect(built.$2['requestDateTime'], '20260826120107');
    });

    test('requestDateTime always equals transactionDateTime', () {
      final (String, Map<String, Object?>) built = EcrWebServiceMessage.build(
        type: EcrTransactionType.sale,
        merchantId: 8899,
        terminalId: 999,
        terminalSerial: 'QQW',
        secureHashKey: '',
        amountMinorUnits: 1000,
        now: DateTime(2026, 8, 26, 12, 6, 54),
      );
      expect(built.$2['transactionDateTime'], '20260826120654');
      expect(built.$2['requestDateTime'], built.$2['transactionDateTime']);
    });
  });

  group('EcrEnvironmentUrls', () {
    test('UAT origin uses the current host', () {
      expect(
        EcrEnvironmentUrls.hubSocketUrl(EcrEnvironment.uat),
        contains('25453'),
      );
    });
  });

  group('HttpEcrWebServiceApi.errorBody', () {
    test('unknown outcome carries nextStep', () {
      final Map<String, Object?> body = HttpEcrWebServiceApi.errorBody(
        responseCode: 'NO_RESPONSE',
        message: 'timed out',
      );
      expect(body['success'], false);
      expect(body['nextStep'], unknownOutcomeStep);
      expect(unknownOutcomeStep, 'INQUIRE_BY_MERCHANT_REFERENCE');
    });

    test('known outcome (e.g. 4xx) omits nextStep', () {
      final Map<String, Object?> body = HttpEcrWebServiceApi.errorBody(
        responseCode: '400',
        message: 'Bad Request',
        outcomeUnknown: false,
      );
      expect(body.containsKey('nextStep'), isFalse);
    });
  });

  group('WebServiceEcrClient inquiry transport failure', () {
    test('unreachable host yields EcrInquiryFailed(EcrConnectionLost)', () async {
      final WebServiceEcrClient client = WebServiceEcrClient(
        terminalSerial: 'QQW',
        config: EcrConfig(
          merchantId: '8899',
          terminalId: '999',
          environment: EcrEnvironment.sit,
          connectTimeout: const Duration(milliseconds: 1),
          responseTimeout: const Duration(milliseconds: 1),
        ),
      );
      final EcrInquiry inquiry = await client.inquireByReference(
        originalReference: 'ORD-88231ABC',
        merchantReference: 'INQ-NEW-REF01',
      );
      expect(inquiry, isA<EcrInquiryFailed>());
      expect(
        (inquiry as EcrInquiryFailed).failure,
        isA<EcrConnectionLost>(),
      );
    });
  });
}
