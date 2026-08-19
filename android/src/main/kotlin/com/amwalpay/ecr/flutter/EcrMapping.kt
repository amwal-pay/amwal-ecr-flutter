package com.amwalpay.ecr.flutter

import com.amwalpay.ecr.EcrConfig
import com.amwalpay.ecr.EcrInquiry
import com.amwalpay.ecr.EcrReceipt
import com.amwalpay.ecr.EcrResult
import com.amwalpay.ecr.EcrTransaction
import com.amwalpay.ecr.Failure
import com.amwalpay.ecr.NextStep
import java.math.BigDecimal
import kotlin.time.Duration.Companion.milliseconds

/**
 * Turns channel arguments into SDK types, and SDK types back into the maps the
 * Dart side reads.
 *
 * Kept free of Flutter types so it can be unit-tested without a binding — the
 * mapping is where a wrapper quietly loses a field, and a test that needs an
 * emulator is a test that stops being run.
 */
internal object EcrMapping {

    /**
     * Reads the `config` sub-map.
     *
     * Every value is optional and falls back to the SDK's own default, so a
     * Dart side that gains a setting this host has not been rebuilt for keeps
     * working rather than failing on an unknown key.
     */
    fun config(raw: Map<*, *>?): EcrConfig {
        val map = raw ?: emptyMap<Any?, Any?>()
        val defaults = EcrConfig()
        return EcrConfig(
            ecrId = map.string(EcrConfigKeys.ECR_ID) ?: defaults.ecrId,
            currencyCode = map.string(EcrConfigKeys.CURRENCY_CODE) ?: defaults.currencyCode,
            minorUnitDigits = map.int(EcrConfigKeys.MINOR_UNIT_DIGITS) ?: defaults.minorUnitDigits,
            port = map.int(EcrConfigKeys.PORT) ?: defaults.port,
            connectTimeout = map.int(EcrConfigKeys.CONNECT_TIMEOUT_MS)?.milliseconds
                ?: defaults.connectTimeout,
            responseTimeout = map.int(EcrConfigKeys.RESPONSE_TIMEOUT_MS)?.milliseconds
                ?: defaults.responseTimeout,
            probeTimeout = map.int(EcrConfigKeys.PROBE_TIMEOUT_MS)?.milliseconds
                ?: defaults.probeTimeout,
            // Empty means unsigned, which is a real setting rather than a
            // missing one — so an empty string is taken as given here, unlike
            // the values above.
            secureHashKey = map[EcrConfigKeys.SECURE_HASH_KEY] as? String
                ?: defaults.secureHashKey,
            autoInquireOnFailure = map[EcrConfigKeys.AUTO_INQUIRE_ON_FAILURE] as? Boolean
                ?: defaults.autoInquireOnFailure,
        )
    }

    /**
     * Reads the amount, which crosses as a decimal string in major units.
     *
     * Never a double. The channel would happily carry one and `1.234` would
     * arrive as 1.2339999999999999857891452847979962825775146484375, which
     * rounds to the right figure today and to the wrong one the day the
     * currency has four decimal places.
     */
    fun amount(raw: Any?): BigDecimal? {
        val text = (raw as? String)?.trim() ?: return null
        if (text.isEmpty()) return null
        return try {
            BigDecimal(text)
        } catch (e: NumberFormatException) {
            throw EcrInvalidArgument("\"$text\" is not a decimal amount", e)
        }
    }

    fun result(result: EcrResult): Map<String, Any?> = when (result) {
        is EcrResult.Approved -> mapOf(
            EcrResultKeys.OUTCOME to EcrOutcomes.APPROVED,
            EcrResultKeys.MERCHANT_REFERENCE_ID to result.merchantReferenceId,
            EcrResultKeys.AMOUNT to result.amount,
            EcrResultKeys.RESPONSE_CODE to result.responseCode,
            EcrResultKeys.RRN to result.rrn,
            EcrResultKeys.AUTH_CODE to result.authCode,
            EcrResultKeys.MASKED_PAN to result.maskedPan,
            EcrResultKeys.PARTIAL_APPROVAL to result.partialApproval,
            EcrResultKeys.REQUESTED_AMOUNT to result.requestedAmount,
            EcrResultKeys.RAW to result.raw,
        )

        is EcrResult.Declined -> mapOf(
            EcrResultKeys.OUTCOME to EcrOutcomes.DECLINED,
            EcrResultKeys.MERCHANT_REFERENCE_ID to result.merchantReferenceId,
            EcrResultKeys.RESPONSE_CODE to result.responseCode,
            EcrResultKeys.REASON to result.reason,
            EcrResultKeys.NEXT_STEP to nextStep(result.nextStep),
            EcrResultKeys.RAW to result.raw,
        )

        is EcrResult.Failed -> mapOf(
            EcrResultKeys.OUTCOME to EcrOutcomes.FAILED,
            EcrResultKeys.MERCHANT_REFERENCE_ID to result.merchantReferenceId,
            EcrResultKeys.FAILURE to failure(result.failure),
            // Absent rather than null when nothing was asked: the Dart side
            // reads absence as "no follow-up was made", which is not the same
            // as "the follow-up found nothing".
            EcrResultKeys.RECOVERED to result.recovered?.let(::inquiry),
        )
    }

    fun inquiry(inquiry: EcrInquiry): Map<String, Any?> = when (inquiry) {
        is EcrInquiry.Found -> mapOf(
            EcrResultKeys.OUTCOME to EcrOutcomes.FOUND,
            EcrResultKeys.MERCHANT_REFERENCE_ID to inquiry.merchantReferenceId,
            EcrResultKeys.TRANSACTION to transaction(inquiry.transaction),
            EcrResultKeys.RAW to inquiry.raw,
        )

        is EcrInquiry.NotFound -> mapOf(
            EcrResultKeys.OUTCOME to EcrOutcomes.NOT_FOUND,
            EcrResultKeys.MERCHANT_REFERENCE_ID to inquiry.merchantReferenceId,
            EcrResultKeys.REASON to inquiry.reason,
            EcrResultKeys.RAW to inquiry.raw,
        )

        is EcrInquiry.Failed -> mapOf(
            EcrResultKeys.OUTCOME to EcrOutcomes.FAILED,
            EcrResultKeys.MERCHANT_REFERENCE_ID to inquiry.merchantReferenceId,
            EcrResultKeys.FAILURE to failure(inquiry.failure),
        )
    }

    fun receipt(receipt: EcrReceipt): Map<String, Any?> = when (receipt) {
        is EcrReceipt.Ready -> mapOf(
            EcrResultKeys.OUTCOME to EcrOutcomes.READY,
            EcrResultKeys.MERCHANT_REFERENCE_ID to receipt.merchantReferenceId,
            EcrResultKeys.URL to receipt.url,
            EcrResultKeys.RAW to receipt.raw,
        )

        is EcrReceipt.Unavailable -> mapOf(
            EcrResultKeys.OUTCOME to EcrOutcomes.UNAVAILABLE,
            EcrResultKeys.MERCHANT_REFERENCE_ID to receipt.merchantReferenceId,
            EcrResultKeys.REASON to receipt.reason,
            EcrResultKeys.RAW to receipt.raw,
        )

        is EcrReceipt.Failed -> mapOf(
            EcrResultKeys.OUTCOME to EcrOutcomes.FAILED,
            EcrResultKeys.MERCHANT_REFERENCE_ID to receipt.merchantReferenceId,
            EcrResultKeys.FAILURE to failure(receipt.failure),
        )
    }

    fun transaction(transaction: EcrTransaction): Map<String, Any?> = mapOf(
        EcrTransactionKeys.TRANSACTION_ID to transaction.transactionId,
        EcrTransactionKeys.STAN to transaction.stan,
        EcrTransactionKeys.TYPE to transaction.type,
        EcrTransactionKeys.STATUS to transaction.status,
        EcrTransactionKeys.AMOUNT to transaction.amount,
        EcrTransactionKeys.TOTAL_AMOUNT to transaction.totalAmount,
        EcrTransactionKeys.CURRENCY to transaction.currency,
        EcrTransactionKeys.TRANSACTION_TIME to transaction.transactionTime,
        EcrTransactionKeys.MASKED_PAN to transaction.maskedPan,
        EcrTransactionKeys.CARD_HOLDER_NAME to transaction.cardHolderName,
        EcrTransactionKeys.RRN to transaction.rrn,
        EcrTransactionKeys.AUTH_CODE to transaction.authCode,
        EcrTransactionKeys.BATCH_ID to transaction.batchId,
        EcrTransactionKeys.TERMINAL_ID to transaction.terminalId,
        EcrTransactionKeys.IS_REFUNDED to transaction.isRefunded,
        EcrTransactionKeys.CAN_VOID to transaction.canVoid,
        EcrTransactionKeys.CAN_REFUND to transaction.canRefund,
    )

    fun failure(failure: Failure): Map<String, Any?> = mapOf(
        EcrFailureKeys.KIND to when (failure) {
            is Failure.Unreachable -> EcrFailureKinds.UNREACHABLE
            is Failure.Timeout -> EcrFailureKinds.TIMEOUT
            is Failure.Malformed -> EcrFailureKinds.MALFORMED
            is Failure.ConnectionLost -> EcrFailureKinds.CONNECTION_LOST
            is Failure.Unauthenticated -> EcrFailureKinds.UNAUTHENTICATED
        },
        EcrFailureKeys.MESSAGE to failure.message,
    )

    /**
     * The name a next step crosses the channel under.
     *
     * The SDK's own enum name, which is the protocol's — no translation, so
     * there is one spelling to keep in step rather than four.
     */
    fun nextStep(step: NextStep): String = when (step) {
        NextStep.NONE -> EcrNextSteps.NONE
        NextStep.INQUIRE_BY_MERCHANT_REFERENCE ->
            EcrNextSteps.INQUIRE_BY_MERCHANT_REFERENCE
    }

    /** A failure this wrapper raised, which the SDK has no case for. */
    fun wrapperFailure(kind: String, message: String): Map<String, Any?> = mapOf(
        EcrFailureKeys.KIND to kind,
        EcrFailureKeys.MESSAGE to message,
    )

    /**
     * A result carrying a wrapper-level failure.
     *
     * The reference is empty because nothing reached the terminal, or reached it
     * and was abandoned before it could name itself — there is no message for
     * the caller to match this to.
     */
    fun failedResult(kind: String, message: String): Map<String, Any?> = mapOf(
        EcrResultKeys.OUTCOME to EcrOutcomes.FAILED,
        EcrResultKeys.MERCHANT_REFERENCE_ID to "",
        EcrResultKeys.FAILURE to wrapperFailure(kind, message),
    )

    private fun Map<*, *>.string(key: String): String? = (this[key] as? String)?.takeIf { it.isNotEmpty() }

    private fun Map<*, *>.int(key: String): Int? = when (val value = this[key]) {
        is Int -> value
        is Long -> value.toInt()
        is Number -> value.toInt()
        else -> null
    }
}

/**
 * The arguments cannot be used, and nothing was sent.
 *
 * Reported to Dart as [EcrErrorCodes.INVALID_ARGUMENT], which the Dart side
 * rethrows as `EcrArgumentError` — an exception rather than an outcome, because
 * there is nothing to reconcile.
 */
internal class EcrInvalidArgument(
    message: String,
    cause: Throwable? = null,
) : IllegalArgumentException(message, cause)
