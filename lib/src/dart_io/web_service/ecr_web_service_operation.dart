/// Fixed path suffixes for Web Service ECR REST operations.
abstract final class EcrWebServiceEndpoints {
  /// Sale path.
  static const String sale = '/Ecr/Sale';

  /// Void path.
  static const String voidTransaction = '/Ecr/Void';

  /// Refund path.
  static const String refund = '/Ecr/Refund';

  /// Transaction status / inquiry path.
  static const String transactionStatus = '/Ecr/TransactionStatus';
}

/// Web Service ECR operations exposed as REST endpoints.
enum EcrWebServiceOperation {
  /// Sale.
  sale(EcrWebServiceEndpoints.sale, 'Sale'),

  /// Void.
  voidTransaction(EcrWebServiceEndpoints.voidTransaction, 'Void'),

  /// Refund.
  refund(EcrWebServiceEndpoints.refund, 'Refund'),

  /// Transaction status (inquiry).
  transactionStatus(
    EcrWebServiceEndpoints.transactionStatus,
    'Transaction status',
  );

  const EcrWebServiceOperation(this.path, this.label);

  /// Path suffix under the Hub origin.
  final String path;

  /// Human-readable label for logs.
  final String label;
}
