package com.amwalpay.ecr.flutter

import com.amwalpay.ecr.EcrConfig
import com.amwalpay.ecr.EcrInquiry
import com.amwalpay.ecr.EcrLink
import com.amwalpay.ecr.EcrLogger
import com.amwalpay.ecr.EcrReceipt
import com.amwalpay.ecr.EcrResult
import com.amwalpay.ecr.EcrSessionPlan
import com.amwalpay.ecr.EcrSessions
import com.amwalpay.ecr.EcrTerminal
import com.amwalpay.ecr.EcrWebServiceTerminal
import com.amwalpay.ecr.Failure
import java.math.BigDecimal

/**
 * Builds [EcrTerminalPort] instances through [EcrSessions.plan], matching the
 * Android simulator app's session-planning pattern.
 */
internal object EcrSessionPorts {

    fun create(
        host: String,
        serialNumber: String,
        transport: String,
        config: EcrConfig,
        logger: EcrLogger,
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
        return when {
            plan.usesWebService -> SdkWebServiceTerminal(serialNumber, plan, logger)
            plan.usesLan -> SdkLanTerminal(serialNumber, plan, logger)
            else -> UnsupportedEcrTerminalPort(transport)
        }
    }

    private fun linkFor(host: String, transport: String, config: EcrConfig): EcrLink? =
        when (transport) {
            EcrTransports.WEB_SERVICE -> EcrLink.WebService(
                merchantId = config.merchantId,
                terminalId = config.terminalId,
            )

            EcrTransports.ETHERNET, EcrTransports.WIFI -> EcrLink.Lan(
                host = host,
                port = config.port,
            )

            else -> null
        }
}

internal class SdkLanTerminal(
    serialNumber: String,
    plan: EcrSessionPlan,
    logger: EcrLogger,
) : EcrTerminalPort {

    private val terminal = EcrSessions.lanTerminal(
        terminalSerial = serialNumber,
        plan = plan,
        logger = logger,
    )

    override suspend fun isReachable(): Boolean = terminal.probeReachability().reachable

    override suspend fun sale(amount: BigDecimal, merchantReference: String): EcrResult =
        terminal.sale(amount = amount, merchantReference = merchantReference)

    override suspend fun void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrResult = terminal.void(
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
    ): EcrResult = terminal.refund(
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
    ): EcrInquiry = terminal.inquire(
        receiptNumber = receiptNumber,
        transactionDate = transactionDate,
        originalTerminalId = originalTerminalId,
        merchantReference = merchantReference,
    )

    override suspend fun inquireByReference(
        originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrInquiry = terminal.inquireByReference(
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
    ): EcrReceipt = terminal.receipt(
        receiptNumber = receiptNumber,
        transactionDate = transactionDate,
        originalTerminalId = originalTerminalId,
        merchantReference = merchantReference,
    )
}

internal class SdkWebServiceTerminal(
    serialNumber: String,
    plan: EcrSessionPlan,
    logger: EcrLogger,
) : EcrTerminalPort {

    private val terminal = EcrSessions.webServiceTerminal(
        terminalSerial = serialNumber,
        plan = plan,
        logger = logger,
    )

    override suspend fun isReachable(): Boolean = false

    override suspend fun sale(amount: BigDecimal, merchantReference: String): EcrResult =
        terminal.sale(amount = amount, merchantReference = merchantReference)

    override suspend fun void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrResult = terminal.void(
        receiptNumber = receiptNumber,
        merchantReference = merchantReference,
    )

    override suspend fun refund(
        amount: BigDecimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrResult = terminal.refund(
        amount = amount,
        receiptNumber = receiptNumber,
        transactionDate = transactionDate,
        merchantReference = merchantReference,
    )

    override suspend fun inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrInquiry = terminal.inquire(
        receiptNumber = receiptNumber,
        transactionDate = transactionDate,
        merchantReference = merchantReference,
    )

    override suspend fun inquireByReference(
        originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrInquiry = terminal.inquireByReference(
        originalReference = originalReference,
        transactionDate = transactionDate,
        merchantReference = merchantReference,
    )

    override suspend fun receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrReceipt = throw UnsupportedOperationException("Receipt is LAN-only")
}

internal class UnsupportedEcrTerminalPort(
    private val transport: String,
) : EcrTerminalPort {

    private val message =
        "A terminal opens its ECR listener only for the IP transports " +
            "(ethernet, wifi) or Web Service REST. \"$transport\" is driven by " +
            "other machinery, so nothing was sent."

    override suspend fun isReachable(): Boolean = false

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
