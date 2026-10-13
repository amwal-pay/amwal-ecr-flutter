import '../../model/ecr_amount.dart';
import '../../model/ecr_config.dart';
import '../../model/ecr_failure.dart';
import '../../model/ecr_inquiry.dart';
import '../../model/ecr_result.dart';
import '../../model/ecr_transaction_type.dart';
import '../ecr_wire_readers.dart';
import 'ecr_web_service_http.dart';
import 'ecr_web_service_message.dart';
import 'ecr_web_service_operation.dart';

/// Web Service ECR client — REST over HTTPS with JSON body signing.
///
/// Mirrors Kotlin / Swift `EcrWebServiceTerminal`.
final class WebServiceEcrClient {
  /// [terminalSerial] identifies the POS; [config] must carry merchant/terminal
  /// ids and the Web Service signing key.
  WebServiceEcrClient({
    required this.terminalSerial,
    required this.config,
  }) : _api = HttpEcrWebServiceApi(config);

  /// Terminal serial number.
  final String terminalSerial;

  /// Till identity, Hub environment, and signing.
  final EcrConfig config;

  final HttpEcrWebServiceApi _api;

  /// Aborts any in-flight HTTP request.
  void abort() => _api.abort();

  /// Takes a payment.
  Future<EcrResult> sale({
    required EcrAmount amount,
    String merchantReference = '',
  }) async {
    final (int, int)? ids = _backendIds();
    if (ids == null) return _invalidIds();

    final (String reference, Map<String, Object?> body) =
        EcrWebServiceMessage.build(
      type: EcrTransactionType.sale,
      merchantId: ids.$1,
      terminalId: ids.$2,
      terminalSerial: terminalSerial,
      secureHashKey: config.secureHashKey,
      currencyCode: config.currencyCode,
      ecrId: config.ecrId,
      amountMinorUnits: amount.toMinorUnits(config.minorUnitDigits).toInt(),
      merchantReference: merchantReference,
    );

    final Map<String, Object?> response =
        await _api.postJson(EcrWebServiceOperation.sale, body);
    return EcrWireReaders.toEcrResult(
      response,
      merchantReference: reference,
      minorUnitDigits: config.minorUnitDigits,
    );
  }

  /// Voids an earlier transaction by receipt number.
  Future<EcrResult> voidTransaction({
    required String receiptNumber,
    String merchantReference = '',
  }) async {
    final (int, int)? ids = _backendIds();
    if (ids == null) return _invalidIds();

    final (String reference, Map<String, Object?> body) =
        EcrWebServiceMessage.build(
      type: EcrTransactionType.voidTransaction,
      merchantId: ids.$1,
      terminalId: ids.$2,
      terminalSerial: terminalSerial,
      secureHashKey: config.secureHashKey,
      currencyCode: config.currencyCode,
      ecrId: config.ecrId,
      stan: receiptNumber,
      merchantReference: merchantReference,
    );

    final Map<String, Object?> response =
        await _api.postJson(EcrWebServiceOperation.voidTransaction, body);
    return EcrWireReaders.toEcrResult(
      response,
      merchantReference: reference,
      minorUnitDigits: config.minorUnitDigits,
    );
  }

  /// Refunds against an earlier transaction.
  Future<EcrResult> refund({
    required EcrAmount amount,
    required String receiptNumber,
    required String transactionDate,
    String merchantReference = '',
  }) async {
    final (int, int)? ids = _backendIds();
    if (ids == null) return _invalidIds();

    final (String reference, Map<String, Object?> body) =
        EcrWebServiceMessage.build(
      type: EcrTransactionType.refund,
      merchantId: ids.$1,
      terminalId: ids.$2,
      terminalSerial: terminalSerial,
      secureHashKey: config.secureHashKey,
      currencyCode: config.currencyCode,
      ecrId: config.ecrId,
      amountMinorUnits: amount.toMinorUnits(config.minorUnitDigits).toInt(),
      stan: receiptNumber,
      originalTransactionDate: transactionDate,
      merchantReference: merchantReference,
    );

    final Map<String, Object?> response =
        await _api.postJson(EcrWebServiceOperation.refund, body);
    return EcrWireReaders.toEcrResult(
      response,
      merchantReference: reference,
      minorUnitDigits: config.minorUnitDigits,
    );
  }

  /// Inquiry by receipt number (TransactionStatus).
  Future<EcrInquiry> inquire({
    required String receiptNumber,
    required String transactionDate,
    String merchantReference = '',
  }) async {
    final (int, int)? ids = _backendIds();
    if (ids == null) {
      return EcrInquiryFailed(
        merchantReference: merchantReference,
        failure: const EcrMalformed(
          'merchantId and terminalId are required for Web Service ECR',
        ),
      );
    }

    final (String reference, Map<String, Object?> body) =
        EcrWebServiceMessage.build(
      type: EcrTransactionType.inquiry,
      merchantId: ids.$1,
      terminalId: ids.$2,
      terminalSerial: terminalSerial,
      secureHashKey: config.secureHashKey,
      currencyCode: config.currencyCode,
      ecrId: config.ecrId,
      stan: receiptNumber,
      originalTransactionDate: transactionDate,
      merchantReference: merchantReference,
    );

    final Map<String, Object?> response = await _api.postJson(
      EcrWebServiceOperation.transactionStatus,
      body,
    );
    return _readInquiry(response, reference);
  }

  /// Inquiry by reference — matches Kotlin `EcrWebServiceTerminal.inquireByReference`.
  Future<EcrInquiry> inquireByReference({
    required String originalReference,
    String transactionDate = '',
    String merchantReference = '',
  }) async {
    if (originalReference.trim().isEmpty) {
      return EcrInquiryFailed(
        merchantReference: merchantReference,
        failure: const EcrMalformed(
          "An inquiry by reference needs the original's reference",
        ),
      );
    }

    final (int, int)? ids = _backendIds();
    if (ids == null) {
      return EcrInquiryFailed(
        merchantReference: merchantReference,
        failure: const EcrMalformed(
          'merchantId and terminalId are required for Web Service ECR',
        ),
      );
    }

    final (String reference, Map<String, Object?> body) =
        EcrWebServiceMessage.build(
      type: EcrTransactionType.inquiry,
      merchantId: ids.$1,
      terminalId: ids.$2,
      terminalSerial: terminalSerial,
      secureHashKey: config.secureHashKey,
      currencyCode: config.currencyCode,
      ecrId: config.ecrId,
      stan: '',
      originalTransactionDate: transactionDate,
      originalMerchantReference: originalReference,
      merchantReference: merchantReference,
    );

    final Map<String, Object?> response = await _api.postJson(
      EcrWebServiceOperation.transactionStatus,
      body,
    );
    return _readInquiry(response, reference);
  }

  /// Reads an inquiry answer; a synthesized unknown-outcome body (no `data`
  /// object) means the inquiry itself got no answer, not "not found".
  EcrInquiry _readInquiry(Map<String, Object?> response, String reference) {
    if (response['nextStep'] == unknownOutcomeStep &&
        response['data'] is! Map) {
      final String message = response['message']?.toString() ?? '';
      return EcrInquiryFailed(
        merchantReference: reference,
        failure: EcrConnectionLost(
          message.isEmpty ? 'The Web Service did not answer' : message,
        ),
      );
    }
    return EcrWireReaders.toInquiry(
      response,
      merchantReference: reference,
      minorUnitDigits: config.minorUnitDigits,
    );
  }

  (int, int)? _backendIds() {
    final int? merchantId = int.tryParse(config.merchantId);
    final int? terminalId = int.tryParse(config.terminalId);
    if (merchantId == null || terminalId == null) return null;
    return (merchantId, terminalId);
  }

  EcrFailed _invalidIds() => const EcrFailed(
        merchantReference: '',
        failure: EcrMalformed(
          'merchantId and terminalId must be set on EcrConfig for '
          'Web Service ECR',
        ),
      );
}
