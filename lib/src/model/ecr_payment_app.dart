/// The Amwal payment app a till hands a transaction to on the same device.
///
/// A constant rather than a string each till types out, because it is the
/// address of the only transport that has no address: get it wrong and the
/// request goes nowhere, with nothing on the network to check it against.
abstract final class EcrPaymentApp {
  /// The application id of the terminal build.
  ///
  /// Overridable on [EcrTerminal.appToApp] so a test build with another id can
  /// be driven, which is the only reason to pass anything else.
  static const String defaultPackage = 'com.amwalpay.pos';
}
