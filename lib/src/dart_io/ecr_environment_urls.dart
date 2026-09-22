import '../model/ecr_environment.dart';

/// ECR Hub base URLs per [EcrEnvironment].
///
/// Mirrors Kotlin `EcrEnvironmentUrls`. Paths (`/Ecr/Sale`, …) are appended by
/// Web Service routes.
abstract final class EcrEnvironmentUrls {
  static const String _sitHost = 'https://test.amwalpg.com:25452';
  static const String _uatHost = 'https://test.amwalpg.com:15452';
  static const String _prodHost = 'https://pos.amwalpg.com';

  /// Hub origin for [environment], without a trailing slash.
  static String hubSocketUrl(EcrEnvironment environment) {
    final String host = switch (environment) {
      EcrEnvironment.sit => _sitHost,
      EcrEnvironment.uat => _uatHost,
      EcrEnvironment.prod => _prodHost,
    };
    return host.endsWith('/') ? host.substring(0, host.length - 1) : host;
  }
}
