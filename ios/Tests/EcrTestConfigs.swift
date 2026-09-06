import AmwalECR

/// Shared `EcrConfig` for Flutter iOS bridge tests.
/// Named placeholders only — never commit real Amwal keys.
enum EcrTestConfigs {
    static let SECURE_HASH_KEY_ECR_WIFI =
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    static let lan = EcrConfig(secureHashKey: SECURE_HASH_KEY_ECR_WIFI)
}
