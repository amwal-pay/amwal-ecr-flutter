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
    String merchantReference = '',
    String transactionDateTime = '',
    String requestDateTime = '',
    DateTime? now,
  }) {
    if (type == EcrTransactionType.receipt) {
      throw const EcrArgumentError('Receipt is not a Web Service operation');
    }

    final String reference =
        EcrMessage.resolveMerchantReference(merchantReference);
    final String wireDateTime = transactionDateTime.isEmpty
        ? _timestamp(now ?? DateTime.now())
        : transactionDateTime;

    final Map<String, Object?> body = <String, Object?>{
      'version': EcrMessage.protocolVersion,
      'messageType': type.messageType,
      'merchantReference': reference,
      'terminalSerial': terminalSerial,
      'currencyCode': currencyCode,
      'transactionDateTime': wireDateTime,
      'requestDateTime':
          requestDateTime.isEmpty ? wireDateTime : requestDateTime,
      'ecrId': ecrId,
    };

    switch (type) {
      case EcrTransactionType.sale:
        body['amount'] =
            (amountMinorUnits ?? 0).toString().padLeft(12, '0');
      case EcrTransactionType.voidTransaction:
        body['stan'] = EcrMessage.paddedStan(stan);
      case EcrTransactionType.refund:
        body['amount'] =
            (amountMinorUnits ?? 0).toString().padLeft(12, '0');
        body['stan'] = EcrMessage.paddedStan(stan);
        body['originalTransactionDate'] = originalTransactionDate;
      case EcrTransactionType.inquiry:
        body['stan'] = EcrMessage.paddedStan(stan);
        body['originalTransactionDate'] = originalTransactionDate;
      case EcrTransactionType.receipt:
        break;
      // The Hub has no route for it and wants none: over Web Service the
      // terminal is not on the till's counter, so its screen is not the
      // till's to tidy. Refused before reaching here, in the platform.
      case EcrTransactionType.closeReceipt:
        break;
      // Nor a sign-on route. A Web Service terminal is reached through Amwal
      // rather than addressed directly, so a till configured for it already
      // knows what a sign-on would tell it about the link.
      case EcrTransactionType.signOn:
        break;
    }

    body['merchantId'] = merchantId;
    body['terminalId'] = terminalId;

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
