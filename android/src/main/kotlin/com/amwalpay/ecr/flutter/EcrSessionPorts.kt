package com.amwalpay.ecr.flutter

import android.content.Context
import com.amwalpay.ecr.EcrConfig
import com.amwalpay.ecr.EcrInquiry
import com.amwalpay.ecr.EcrLink
import com.amwalpay.ecr.EcrLogger
import com.amwalpay.ecr.EcrOpenedSession
import com.amwalpay.ecr.EcrReachability
import com.amwalpay.ecr.EcrReceipt
import com.amwalpay.ecr.EcrResult
import com.amwalpay.ecr.EcrSessions
import com.amwalpay.ecr.Failure
import java.math.BigDecimal

/**
 * Builds [EcrTerminalPort] instances through [EcrSessions.plan] / [EcrSessions.open],
 * matching the Android simulator app's session-planning pattern.
 */
internal object EcrSessionPorts {

    fun create(
        host: String,
        serialNumber: String,
        transport: String,
        config: EcrConfig,
        logger: EcrLogger,
        context: Context? = null,
    ): EcrTerminalPort {
        val link = linkFor(host, transport, config) ?: return UnsupportedEcrTerminalPort(transport)
        val plan = EcrSessions.plan(
            link = link,
            config = config,
            rawSecureHashKey = config.secureHashKey,
        )
        if (!plan.isReady) {
            return InvalidPlanTerminalPort(plan.issues)
        }
        if (plan.usesUsbCable && context == null) {
            return UnsupportedEcrTerminalPort(transport)
        }
        val session = EcrSessions.open(
            terminalSerial = serialNumber,
            plan = plan,
            usbChannel = if (plan.usesUsbCable) {
                { UsbAccessoryEcrChannel(context!!, log = { logger.debug(it) }) }
            } else {
                null
            },
            logger = logger,
        )
        return SdkOpenedSessionPort(session)
    }

    private fun linkFor(host: String, transport: String, config: EcrConfig): EcrLink? =
        when {
            transport == EcrTransports.WEB_SERVICE || transport == EcrTransports.WEB_SERVICE_SNAKE ->
                EcrLink.WebService(
                    merchantId = config.merchantId,
                    terminalId = config.terminalId,
                )

            transport == EcrTransports.WIFI -> EcrLink.Lan(
                host = host,
                port = config.port,
            )

            EcrTransports.isUsbCable(transport) -> EcrLink.UsbCable

            else -> null
        }
}

/** One [EcrOpenedSession] behind the Flutter terminal port contract. */
internal class SdkOpenedSessionPort(
    private val session: EcrOpenedSession,
) : EcrTerminalPort {

    override suspend fun isReachable(): Boolean =
        session.probeReachability()?.reachable == true

    override suspend fun probeReachability(): EcrReachability =
        session.probeReachability() ?: EcrReachability(
            reachable = false,
            host = "",
            port = 0,
            endpoint = "webService",
        )

    override suspend fun sale(amount: BigDecimal, merchantReference: String): EcrResult =
        session.sale(amount = amount, merchantReference = merchantReference)

    override suspend fun void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrResult = session.void(
        receiptNumber = receiptNumber,
        originalTerminalId = originalTerminalId,
        merchantReference = merchantReference,
    )

    override suspend fun refund(
        amount: BigDecimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrResult = session.refund(
        amount = amount,
        receiptNumber = receiptNumber,
        transactionDate = transactionDate,
        originalTerminalId = originalTerminalId,
        merchantReference = merchantReference,
    )

    override suspend fun inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrInquiry = session.inquire(
        receiptNumber = receiptNumber,
        transactionDate = transactionDate,
        originalTerminalId = originalTerminalId,
    )

    override suspend fun inquireByReference(
        originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrInquiry = session.inquireByReference(
        originalReference = originalReference,
        transactionDate = transactionDate,
        originalTerminalId = originalTerminalId,
        merchantReference = merchantReference,
    )

    override suspend fun receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrReceipt = session.receipt(
        receiptNumber = receiptNumber,
        transactionDate = transactionDate,
        originalTerminalId = originalTerminalId,
    )
}

internal class UnsupportedEcrTerminalPort(
    private val transport: String,
) : EcrTerminalPort {

    private val message =
        "A terminal opens its ECR listener for Wi‑Fi, USB cable, or Web " +
            "Service REST. \"$transport\" is driven by other machinery, so " +
            "nothing was sent."

    override suspend fun isReachable(): Boolean = false

    override suspend fun probeReachability(): EcrReachability = EcrReachability(
        reachable = false,
        host = "",
        port = 0,
        endpoint = transport,
    )

    override suspend fun sale(amount: BigDecimal, merchantReference: String): EcrResult =
        unsupported()

    override suspend fun void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrResult = unsupported()

    override suspend fun refund(
        amount: BigDecimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrResult = unsupported()

    override suspend fun inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrInquiry = unsupportedInquiry()

    override suspend fun inquireByReference(
        originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrInquiry = unsupportedInquiry()

    override suspend fun receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrReceipt = throw UnsupportedOperationException(message)

    private fun unsupported(): Nothing =
        throw EcrUnsupportedTransportException(message)

    private fun unsupportedInquiry(): Nothing =
        throw EcrUnsupportedTransportException(message)
}

internal class EcrUnsupportedTransportException(message: String) : IllegalStateException(message)

/**
 * Answers every call with a configuration failure from [EcrSessions.plan].
 *
 * Matches the simulator app, which blocks transactions until the terminal
 * config is ready rather than sending half-formed requests to the SDK.
 */
internal class InvalidPlanTerminalPort(
    private val issues: List<String>,
) : EcrTerminalPort {

    private val message: String =
        issues.joinToString("; ").ifEmpty { "Terminal configuration is incomplete" }

    override suspend fun isReachable(): Boolean = false

    override suspend fun probeReachability(): EcrReachability = EcrReachability(
        reachable = false,
        host = "",
        port = 0,
        error = message,
        endpoint = "",
    )

    override suspend fun sale(amount: BigDecimal, merchantReference: String): EcrResult =
        configFailed(merchantReference)

    override suspend fun void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrResult = configFailed(merchantReference)

    override suspend fun refund(
        amount: BigDecimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrResult = configFailed(merchantReference)

    override suspend fun inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrInquiry = configInquiryFailed(merchantReference)

    override suspend fun inquireByReference(
        originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrInquiry = configInquiryFailed(merchantReference)

    override suspend fun receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrReceipt = EcrReceipt.Failed(merchantReference, Failure.Malformed(message))

    private fun configFailed(merchantReference: String): EcrResult =
        EcrResult.Failed(merchantReference, Failure.Malformed(message))

    private fun configInquiryFailed(merchantReference: String): EcrInquiry =
        EcrInquiry.Failed(merchantReference, Failure.Malformed(message))
}
