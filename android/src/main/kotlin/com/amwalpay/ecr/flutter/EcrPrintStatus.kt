package com.amwalpay.ecr.flutter

/**
 * App-to-app PRINT outcome. Same wire values as MobileMerchantApp
 * (`amwal.ecr.printStatus` = SUCCESSFUL | FAILED).
 */
internal enum class EcrPrintStatus {
    SUCCESSFUL,
    FAILED;

    val wire: String get() = name

    val isSuccess: Boolean get() = this == SUCCESSFUL

    companion object {
        fun fromWire(raw: String?, ok: Boolean? = null): EcrPrintStatus =
            when (raw?.trim()?.uppercase()) {
                "SUCCESSFUL", "SUCCESS", "OK" -> SUCCESSFUL
                "FAILED", "FAIL", "ERROR" -> FAILED
                else -> if (ok == true) SUCCESSFUL else FAILED
            }

        fun of(ok: Boolean): EcrPrintStatus = if (ok) SUCCESSFUL else FAILED
    }
}

/**
 * Print answer: [status] and [message] are independent fields — never merge
 * them into one string for the wire or for the channel map.
 */
internal data class EcrPrintOutcome(
    val status: EcrPrintStatus,
    val message: String,
) {
    val isSuccess: Boolean get() = status.isSuccess

    fun toChannelMap(): Map<String, Any?> = mapOf(
        EcrPrintKeys.STATUS to status.wire,
        EcrPrintKeys.MESSAGE to message,
        EcrPrintKeys.OK to isSuccess,
    )

    companion object {
        fun successful(message: String = "") =
            EcrPrintOutcome(EcrPrintStatus.SUCCESSFUL, message)

        fun failed(message: String = "") =
            EcrPrintOutcome(EcrPrintStatus.FAILED, message)

        fun from(ok: Boolean, message: String, statusWire: String? = null): EcrPrintOutcome {
            val status = EcrPrintStatus.fromWire(statusWire, ok)
            return EcrPrintOutcome(status = status, message = message)
        }
    }
}
