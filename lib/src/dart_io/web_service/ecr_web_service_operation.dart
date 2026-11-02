/// Fixed path suffixes for Web Service ECR REST operations.
abstract final class EcrWebServiceEndpoints {
  /// Sale path.
  static const String sale = '/Ecr/Sale';

  /// Void path.
  static const String voidTransaction = '/Ecr/Void';

  /// Refund path.
  static const String refund = '/Ecr/Refund';

  /// Transaction status / inquiry path.
  static const String transactionStatus = '/Ecr/Inquiry';

  /// Settlement path. Identity body only — no `messageType`, no amount.
  static const String settle = '/Ecr/settle';

  /// Close-receipt path. No `messageType` and no `currencyCode`.
  static const String closeReceipt = '/Ecr/closeReceipt';
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
  ),

  /// Closes the current batch. Posts `/Ecr/settle`.
  settle(EcrWebServiceEndpoints.settle, 'Settlement'),

  /// Puts the terminal's receipt away. Posts `/Ecr/closeReceipt`.
  closeReceipt(EcrWebServiceEndpoints.closeReceipt, 'Close receipt');

  const EcrWebServiceOperation(this.path, this.label);

  /// Path suffix under the Hub origin.
  final String path;

  /// Human-readable label for logs.
  final String label;
}
