package com.amwalpay.ecr.flutter

import com.amwalpay.ecr.EcrInquiry
import com.amwalpay.ecr.EcrReachability
import com.amwalpay.ecr.EcrReceipt
import com.amwalpay.ecr.EcrResult
import java.math.BigDecimal

/**
 * The part of the ECR SDK this wrapper uses.
 *
 * `EcrTerminal` and `EcrWebServiceTerminal` are final classes, so a seam is
 * needed to test the handler without a terminal on the network.
 */
internal interface EcrTerminalPort {

    suspend fun isReachable(): Boolean

    suspend fun probeReachability(): EcrReachability

    suspend fun sale(amount: BigDecimal, merchantReference: String): EcrResult

    suspend fun void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrResult

    suspend fun refund(
        amount: BigDecimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrResult

    suspend fun inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrInquiry

    suspend fun inquireByReference(
        originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrInquiry

    suspend fun receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String,
    ): EcrReceipt
}

/** Builds the port for one call's terminal. Replaced in tests. */
internal fun interface EcrTerminalFactory {
    fun create(
        host: String,
        serialNumber: String,
        transport: String,
        config: com.amwalpay.ecr.EcrConfig,
    ): EcrTerminalPort
}
