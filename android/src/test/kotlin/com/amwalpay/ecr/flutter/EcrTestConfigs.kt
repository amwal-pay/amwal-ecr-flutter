package com.amwalpay.ecr.flutter

import com.amwalpay.ecr.EcrConfig
import com.amwalpay.ecr.EcrEnvironment

/**
 * Shared [EcrConfig] values for Flutter Android host tests.
 *
 * Named placeholders only — never commit real Amwal keys.
 */
internal object EcrTestConfigs {
    const val SECURE_HASH_KEY_ECR_WIFI: String =
        ""

    const val SECURE_HASH_KEY_ECR_WEBSERVICE: String =
        ""

    val lan: EcrConfig = EcrConfig(
        secureHashKey = SECURE_HASH_KEY_ECR_WIFI,
    )

    val webService: EcrConfig = EcrConfig(
        merchantId = "13593",
        terminalId = "101311",
        environment = EcrEnvironment.UAT,
        secureHashKey = SECURE_HASH_KEY_ECR_WEBSERVICE,
    )
}
