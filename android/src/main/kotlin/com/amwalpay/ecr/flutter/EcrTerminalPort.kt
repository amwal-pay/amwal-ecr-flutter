package com.amwalpay.ecr.flutter

import com.amwalpay.ecr.EcrConfig
import com.amwalpay.ecr.EcrInquiry
import com.amwalpay.ecr.EcrLogger
import com.amwalpay.ecr.EcrReceipt
import com.amwalpay.ecr.EcrResult
import com.amwalpay.ecr.EcrTerminal
import java.math.BigDecimal

/**
 * The part of the ECR SDK this wrapper uses.
 *
 * `EcrTerminal` is a final class, so a seam is needed to test the handler
 * without a terminal on the network. The interface is exactly the SDK's own
 * surface — same names, same parameter order, same types — so it stays obvious
 * that this adds nothing and hides nothing.
 */
internal interface EcrTerminalPort {

    suspend fun isReachable(): Boolean

    suspend fun sale(amount: BigDecimal, merchantReferenceId: String): EcrResult

    suspend fun void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReferenceId: String,
    ): EcrResult

    suspend fun refund(
        amount: BigDecimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String,
    ): EcrResult

    suspend fun inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String,
    ): EcrInquiry

    /**
     * Looks a transaction up by the reference it was sent with.
     *
     * The only lookup available after an answer goes missing: a receipt number
     * arrives *in* the answer, and the reference does not.
     */
    suspend fun inquireByReference(
        originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String,
    ): EcrInquiry

    suspend fun receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String,
    ): EcrReceipt
}

/** Builds the port for one call's terminal. Replaced in tests. */
internal fun interface EcrTerminalFactory {
    fun create(host: String, serialNumber: String, config: EcrConfig): EcrTerminalPort
}

/** The real thing: `com.amwal-pay:ecr-sdk`. */
internal class SdkEcrTerminal(
    host: String,
    serialNumber: String,
    config: EcrConfig,
    logger: EcrLogger,
) : EcrTerminalPort {

    private val terminal = EcrTerminal(
        host = host,
        serialNumber = serialNumber,
        config = config,
        logger = logger,
    )

    override suspend fun isReachable(): Boolean = terminal.isReachable()

    override suspend fun sale(amount: BigDecimal, merchantReferenceId: String): EcrResult =
        terminal.sale(amount = amount, merchantReferenceId = merchantReferenceId)

    override suspend fun void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReferenceId: String,
    ): EcrResult = terminal.void(
        receiptNumber = receiptNumber,
        originalTerminalId = originalTerminalId,
        merchantReferenceId = merchantReferenceId,
    )

    override suspend fun refund(
        amount: BigDecimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String,
    ): EcrResult = terminal.refund(
        amount = amount,
        receiptNumber = receiptNumber,
        transactionDate = transactionDate,
        originalTerminalId = originalTerminalId,
        merchantReferenceId = merchantReferenceId,
    )

    override suspend fun inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String,
    ): EcrInquiry = terminal.inquire(
        receiptNumber = receiptNumber,
        transactionDate = transactionDate,
        originalTerminalId = originalTerminalId,
        merchantReferenceId = merchantReferenceId,
    )

    override suspend fun inquireByReference(
        originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String,
    ): EcrInquiry = terminal.inquireByReference(
        originalReference = originalReference,
        transactionDate = transactionDate,
        originalTerminalId = originalTerminalId,
        merchantReferenceId = merchantReferenceId,
    )

    override suspend fun receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String,
    ): EcrReceipt = terminal.receipt(
        receiptNumber = receiptNumber,
        transactionDate = transactionDate,
        originalTerminalId = originalTerminalId,
        merchantReferenceId = merchantReferenceId,
    )
}
