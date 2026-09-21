/// The Amwal payment app a till hands a transaction to on the same device.
///
/// Fixed, and deliberately not a setting. Which app takes a payment is not a
/// preference: it is Amwal's app or it is not a payment. An application id a
/// till could pass — or worse, one an operator could type on a registration
/// screen — is an invitation to point a payment at something else, and nothing
/// on a network would catch it, because there is no network in this.
abstract final class EcrPaymentApp {
  /// The application id of the Amwal payment app.
  static const String packageName = 'com.amwalpay.pos';
}
