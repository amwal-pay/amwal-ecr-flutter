/// Hub deployment for Web Service ECR.
///
/// Mirrors `EcrEnvironment` in the Android SDK. Hub URLs are resolved inside
/// the native SDK; integrators pass only this value in [EcrConfig.environment].
enum EcrEnvironment {
  sit,
  uat,
  prod;

  /// The name the native SDK expects on the channel.
  String get wireName => name.toUpperCase();

  static EcrEnvironment fromWireName(String? name) {
    final String trimmed = (name ?? '').trim();
    for (final EcrEnvironment value in EcrEnvironment.values) {
      if (value.wireName == trimmed.toUpperCase()) return value;
    }
    return EcrEnvironment.sit;
  }
}
