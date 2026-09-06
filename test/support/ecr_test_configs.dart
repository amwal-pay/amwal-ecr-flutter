import 'package:amwal_ecr/amwal_ecr.dart';

/// Shared [EcrConfig] values for unit tests.
///
/// Secrets use named placeholders — never commit real Amwal keys. Values are
/// synthetic valid hex so [EcrConfig] accepts them.
abstract final class EcrTestConfigs {
  /// Wi‑Fi / LAN / USB cable signing placeholder.
  static const String SECURE_HASH_KEY_ECR_WIFI =
      '';
  /// Web Service REST signing placeholder.
  static const String SECURE_HASH_KEY_ECR_WEBSERVICE =
      '';

  static final EcrConfig lan = EcrConfig(
    secureHashKey: SECURE_HASH_KEY_ECR_WIFI,
  );

  static final EcrConfig webService = EcrConfig(
    merchantId: '13593',
    terminalId: '1',
    secureHashKey: SECURE_HASH_KEY_ECR_WEBSERVICE,
  );
}
