/// App-owned labels for the two signing secrets (UI / plan issues).
///
/// The ECR plugin only accepts a single [EcrConfig.secureHashKey]; the example
/// picks which stored secret to pass based on terminal mode.
abstract final class EcrSecureHashLabels {
  static const String wifi = 'Wi-Fi/LAN secure hash key';
  static const String webService = 'Web Service secure hash key';
}
