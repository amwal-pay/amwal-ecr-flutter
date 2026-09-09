package com.amwalpay.ecr.flutter

import com.amwalpay.ecr.EcrConfig
import com.amwalpay.ecr.EcrEnvironment

/**
 * Shared [EcrConfig] values for Flutter Android host tests.
 *
 * Matches `ecr_sdk` `EcrTestConfigs`. Secrets use named placeholders — never
 * commit real Amwal keys. Values are synthetic valid hex so [EcrConfig]
 * accepts them; override in CI if needed.
 */
internal object EcrTestConfigs {

    /** Wi‑Fi / LAN / USB cable signing placeholder (valid hex, not a real secret). */
    const val SECURE_HASH_KEY_ECR_WIFI: String =
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    /** Alternate Wi‑Fi placeholder — wrong-key verification cases. */
    const val SECURE_HASH_KEY_ECR_WIFI_OTHER: String =
        "cccccccccccccccccccccccccccccccc"

    /** Web Service REST signing placeholder (valid hex, not a real secret). */
    const val SECURE_HASH_KEY_WEBSERVICE: String =
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    val lan: EcrConfig = EcrConfig(
        secureHashKey = SECURE_HASH_KEY_ECR_WIFI,
    )

    val lanOther: EcrConfig = EcrConfig(
        secureHashKey = SECURE_HASH_KEY_ECR_WIFI_OTHER,
    )

    val webService: EcrConfig = EcrConfig(
        merchantId = "13593",
        terminalId = "742001",
        environment = EcrEnvironment.UAT,
        secureHashKey = SECURE_HASH_KEY_WEBSERVICE,
    )
}
