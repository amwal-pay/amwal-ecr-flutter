import 'package:amwal_ecr/amwal_ecr.dart';

/// Shared [EcrConfig] values for unit tests.
///
/// Matches `ecr_sdk` `EcrTestConfigs`. Secrets use named placeholders — never
/// commit real Amwal keys. Values are synthetic valid hex so [EcrConfig]
/// accepts them; override in CI if needed.
abstract final class EcrTestConfigs {
  /// Wi‑Fi / LAN / USB cable signing placeholder (valid hex, not a real secret).
  static const String SECURE_HASH_KEY_ECR_WIFI =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  /// Alternate Wi‑Fi placeholder — wrong-key verification cases.
  static const String SECURE_HASH_KEY_ECR_WIFI_OTHER =
      'cccccccccccccccccccccccccccccccc';

  /// Web Service REST signing placeholder (valid hex, not a real secret).
  static const String SECURE_HASH_KEY_WEBSERVICE =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  static final EcrConfig lan = EcrConfig(
    secureHashKey: SECURE_HASH_KEY_ECR_WIFI,
  );

  static final EcrConfig lanOther = EcrConfig(
    secureHashKey: SECURE_HASH_KEY_ECR_WIFI_OTHER,
  );

  static final EcrConfig webService = EcrConfig(
    merchantId: '13593',
    terminalId: '742001',
    environment: EcrEnvironment.uat,
    secureHashKey: SECURE_HASH_KEY_WEBSERVICE,
  );
}
