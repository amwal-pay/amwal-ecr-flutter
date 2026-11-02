import '../../model/ecr_config.dart';
import '../../model/ecr_errors.dart';
import '../../model/ecr_transaction_type.dart';
import '../ecr_environment_urls.dart';
import '../ecr_message.dart';
import '../web_service_secure_hash.dart';
import 'ecr_web_service_operation.dart';

/// Web Service ECR wire payload builder.
///
/// Mirrors Kotlin `EcrWebServiceMessage`.
abstract final class EcrWebServiceMessage {
  /// Builds a signed body for [type]. Returns `(merchantReference, body)`.
  static (String, Map<String, Object?>) build({
    required EcrTransactionType type,
    required int merchantId,
    required int terminalId,
    required String terminalSerial,
    required String secureHashKey,
    String currencyCode = '512',
    String ecrId = 'ECR01',
    int? amountMinorUnits,
    String stan = '',
    String originalTransactionDate = '',
    /// Set for inquiry-by-reference; ignored for stan-based inquiry.
    String originalMerchantReference = '',
    String merchantReference = '',
    String transactionDateTime = '',
    DateTime? now,
  }) {
    if (type == EcrTransactionType.receipt) {
      throw const EcrArgumentError('Receipt is not a Web Service operation');
    }
    if (type == EcrTransactionType.closeReceipt) {
      return buildCloseReceipt(
        merchantId: merchantId,
        terminalId: terminalId,
        terminalSerial: terminalSerial,
        secureHashKey: secureHashKey,
        ecrId: ecrId,
        merchantReference: merchantReference,
        originalMerchantReference: originalMerchantReference,
        transactionDateTime: transactionDateTime,
        now: now,
      );
    }
    if (type == EcrTransactionType.settlement) {
      return buildPlain(
        merchantId: merchantId,
        terminalId: terminalId,
        terminalSerial: terminalSerial,
        secureHashKey: secureHashKey,
        currencyCode: currencyCode,
        ecrId: ecrId,
        merchantReference: merchantReference,
        transactionDateTime: transactionDateTime,
        now: now,
      );
    }

    final String reference =
        EcrMessage.resolveMerchantReference(merchantReference);
    final String wireDateTime = transactionDateTime.isEmpty
        ? _timestamp(now ?? DateTime.now())
        : transactionDateTime;

    final Map<String, Object?> body = <String, Object?>{
      'version': EcrMessage.protocolVersion,
      'messageType': type.messageType,
      'merchantId': merchantId,
      'terminalId': terminalId,
      'terminalSerial': terminalSerial,
      'ecrId': ecrId,
      'merchantReference': reference,
      'currencyCode': currencyCode,
      'transactionDateTime': wireDateTime,
      // Hub validates this separately from transactionDateTime
      // (`RequestDateTimeIsRequired` when omitted); always the same instant.
      'requestDateTime': wireDateTime,
    };

    switch (type) {
      case EcrTransactionType.sale:
        body['amount'] =
            (amountMinorUnits ?? 0).toString().padLeft(12, '0');
      case EcrTransactionType.voidTransaction:
        body['stan'] = EcrMessage.paddedStan(stan);
        body['originalMerchantReference'] = reference;
        body['originalTerminalId'] = terminalId;
      case EcrTransactionType.refund:
        body['amount'] =
            (amountMinorUnits ?? 0).toString().padLeft(12, '0');
        body['stan'] = EcrMessage.paddedStan(stan);
        body['originalTransactionDate'] = originalTransactionDate;
        body['originalMerchantReference'] = reference;
        body['originalTerminalId'] = terminalId;
      case EcrTransactionType.inquiry:
        final String invoiceStan = EcrMessage.paddedStan(stan);
        final bool byStan = invoiceStan.isNotEmpty;
        final bool byReference =
            !byStan && originalMerchantReference.trim().isNotEmpty;
        body['stan'] = invoiceStan;
        body['originalTransactionDate'] = originalTransactionDate;
        // By STAN → empty originalMerchantReference; by reference → set it.
        body['originalMerchantReference'] = byReference
            ? EcrMessage.resolveMerchantReference(originalMerchantReference)
            : '';
        body['originalTerminalId'] = terminalId;
      case EcrTransactionType.receipt:
        break;
      case EcrTransactionType.closeReceipt:
        throw StateError('unreachable');
      // Nor a sign-on route. A Web Service terminal is reached through Amwal
      // rather than addressed directly, so a till configured for it already
      // knows what a sign-on would tell it about the link.
      case EcrTransactionType.signOn:
        break;
      case EcrTransactionType.settlement:
        throw StateError('unreachable');
    }

    final Map<String, Object?> json = secureHashKey.isEmpty
        ? body
        : WebServiceSecureHash.withHash(body, secureHashKey);

    return (reference, json);
  }

  /// Hub `/Ecr/closeReceipt` body. No `messageType` and no `currencyCode`.
  static (String, Map<String, Object?>) buildCloseReceipt({
    required int merchantId,
    required int terminalId,
    required String terminalSerial,
    required String secureHashKey,
    String ecrId = 'ECR01',
    String merchantReference = '',
    required String originalMerchantReference,
    String transactionDateTime = '',
    DateTime? now,
  }) {
    if (originalMerchantReference.trim().isEmpty) {
      throw const EcrArgumentError(
        'Close receipt needs the original merchant reference',
      );
    }
    final String reference =
        EcrMessage.resolveMerchantReference(merchantReference);
    final String original =
        EcrMessage.resolveMerchantReference(originalMerchantReference);
    final String wireDateTime = transactionDateTime.isEmpty
        ? _timestamp(now ?? DateTime.now())
        : transactionDateTime;
    final Map<String, Object?> body = <String, Object?>{
      'version': EcrMessage.protocolVersion,
      'merchantId': merchantId,
      'terminalId': terminalId,
      'terminalSerial': terminalSerial,
      'ecrId': ecrId,
      'merchantReference': reference,
      'transactionDateTime': wireDateTime,
      'requestDateTime': wireDateTime,
      'originalMerchantReference': original,
    };
    final Map<String, Object?> json = secureHashKey.isEmpty
        ? body
        : WebServiceSecureHash.withHash(body, secureHashKey);
    return (reference, json);
  }

  /// Hub `/Ecr/settle` body: identity, currency, both timestamps. No `messageType`.
  static (String, Map<String, Object?>) buildPlain({
    required int merchantId,
    required int terminalId,
    required String terminalSerial,
    required String secureHashKey,
    String currencyCode = '512',
    String ecrId = 'ECR01',
    String merchantReference = '',
    String transactionDateTime = '',
    DateTime? now,
  }) {
    final String reference =
        EcrMessage.resolveMerchantReference(merchantReference);
    final String wireDateTime = transactionDateTime.isEmpty
        ? _timestamp(now ?? DateTime.now())
        : transactionDateTime;
    final Map<String, Object?> body = <String, Object?>{
      'version': EcrMessage.protocolVersion,
      'merchantId': merchantId,
      'terminalId': terminalId,
      'terminalSerial': terminalSerial,
      'ecrId': ecrId,
      'merchantReference': reference,
      'currencyCode': currencyCode,
      'transactionDateTime': wireDateTime,
      'requestDateTime': wireDateTime,
    };
    final Map<String, Object?> json = secureHashKey.isEmpty
        ? body
        : WebServiceSecureHash.withHash(body, secureHashKey);
    return (reference, json);
  }

  static String _timestamp(DateTime local) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}'
        '${two(local.month)}'
        '${two(local.day)}'
        '${two(local.hour)}'
        '${two(local.minute)}'
        '${two(local.second)}';
  }
}

/// Resolves Hub URLs for a config's environment.
final class EcrWebServiceRoutes {
  /// Uses [config.environment] for the Hub origin.
  EcrWebServiceRoutes(this.config);

  /// Config carrying the environment.
  final EcrConfig config;

  /// Full URL for [operation].
  String fullUrl(EcrWebServiceOperation operation) {
    final String origin =
        EcrEnvironmentUrls.hubSocketUrl(config.environment);
    return '$origin${operation.path}';
  }
}
