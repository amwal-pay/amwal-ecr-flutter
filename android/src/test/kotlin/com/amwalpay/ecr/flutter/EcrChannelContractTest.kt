package com.amwalpay.ecr.flutter

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * The contract, frozen — the Android copy.
 *
 * The same literals are asserted in `test/platform/channel_contract_test.dart`
 * and `EcrChannelContractTests.swift`. Nothing in the toolchain checks that the
 * three agree, so each side writes the strings out again by hand: a rename that
 * reaches one host and not the others fails here rather than turning into a
 * call that is simply never answered at a till.
 *
 * **Changing a value in this file is not how you rename something.** Rename it
 * in all three contracts and all three tests, in one commit, and treat it as a
 * breaking change.
 */
class EcrChannelContractTest {

    @Test
    fun `method names are spelled exactly this way`() {
        assertEquals("isReachable", EcrMethods.IS_REACHABLE)
        assertEquals("sale", EcrMethods.SALE)
        assertEquals("void", EcrMethods.VOID)
        assertEquals("refund", EcrMethods.REFUND)
        assertEquals("inquire", EcrMethods.INQUIRE)
        assertEquals("inquireByReference", EcrMethods.INQUIRE_BY_REFERENCE)
        assertEquals("receipt", EcrMethods.RECEIPT)
        assertEquals("cancel", EcrMethods.CANCEL)
    }

    @Test
    fun `argument keys are spelled exactly this way`() {
        assertEquals("operationId", EcrArgs.OPERATION_ID)
        assertEquals("host", EcrArgs.HOST)
        assertEquals("serialNumber", EcrArgs.SERIAL_NUMBER)
        assertEquals("transport", EcrArgs.TRANSPORT)
        assertEquals("config", EcrArgs.CONFIG)
        assertEquals("amount", EcrArgs.AMOUNT)
        assertEquals("receiptNumber", EcrArgs.RECEIPT_NUMBER)
        assertEquals("transactionDate", EcrArgs.TRANSACTION_DATE)
        assertEquals("originalTerminalId", EcrArgs.ORIGINAL_TERMINAL_ID)
        assertEquals("merchantReferenceId", EcrArgs.MERCHANT_REFERENCE_ID)
        assertEquals("originalMerchantReference", EcrArgs.ORIGINAL_MERCHANT_REFERENCE)
    }

    @Test
    fun `config keys are spelled exactly this way, and name their unit`() {
        assertEquals("ecrId", EcrConfigKeys.ECR_ID)
        assertEquals("currencyCode", EcrConfigKeys.CURRENCY_CODE)
        assertEquals("minorUnitDigits", EcrConfigKeys.MINOR_UNIT_DIGITS)
        assertEquals("port", EcrConfigKeys.PORT)
        // The Ms suffix is load-bearing: Duration and TimeInterval disagree
        // about units, and a key that does not name one invites a guess.
        assertEquals("connectTimeoutMs", EcrConfigKeys.CONNECT_TIMEOUT_MS)
        assertEquals("responseTimeoutMs", EcrConfigKeys.RESPONSE_TIMEOUT_MS)
        assertEquals("probeTimeoutMs", EcrConfigKeys.PROBE_TIMEOUT_MS)
        assertEquals("secureHashKey", EcrConfigKeys.SECURE_HASH_KEY)
        assertEquals("autoInquireOnFailure", EcrConfigKeys.AUTO_INQUIRE_ON_FAILURE)
    }

    @Test
    fun `result keys are spelled exactly this way`() {
        assertEquals("outcome", EcrResultKeys.OUTCOME)
        assertEquals("merchantReferenceId", EcrResultKeys.MERCHANT_REFERENCE_ID)
        assertEquals("amount", EcrResultKeys.AMOUNT)
        assertEquals("responseCode", EcrResultKeys.RESPONSE_CODE)
        // The wire calls it responseMessage; the channel calls it reason.
        assertEquals("reason", EcrResultKeys.REASON)
        assertEquals("rrn", EcrResultKeys.RRN)
        assertEquals("authCode", EcrResultKeys.AUTH_CODE)
        assertEquals("maskedPan", EcrResultKeys.MASKED_PAN)
        assertEquals("partialApproval", EcrResultKeys.PARTIAL_APPROVAL)
        assertEquals("requestedAmount", EcrResultKeys.REQUESTED_AMOUNT)
        assertEquals("raw", EcrResultKeys.RAW)
        assertEquals("failure", EcrResultKeys.FAILURE)
        assertEquals("transaction", EcrResultKeys.TRANSACTION)
        assertEquals("url", EcrResultKeys.URL)
        assertEquals("nextStep", EcrResultKeys.NEXT_STEP)
        assertEquals("recovered", EcrResultKeys.RECOVERED)
    }

    @Test
    fun `outcomes are spelled exactly this way`() {
        assertEquals("approved", EcrOutcomes.APPROVED)
        assertEquals("declined", EcrOutcomes.DECLINED)
        assertEquals("failed", EcrOutcomes.FAILED)
        assertEquals("found", EcrOutcomes.FOUND)
        assertEquals("notFound", EcrOutcomes.NOT_FOUND)
        assertEquals("ready", EcrOutcomes.READY)
        assertEquals("unavailable", EcrOutcomes.UNAVAILABLE)
    }

    @Test
    fun `failure kinds are spelled exactly this way`() {
        assertEquals("unreachable", EcrFailureKinds.UNREACHABLE)
        assertEquals("timeout", EcrFailureKinds.TIMEOUT)
        assertEquals("malformed", EcrFailureKinds.MALFORMED)
        assertEquals("connectionLost", EcrFailureKinds.CONNECTION_LOST)
        assertEquals("unauthenticated", EcrFailureKinds.UNAUTHENTICATED)
        assertEquals("cancelled", EcrFailureKinds.CANCELLED)
        assertEquals("unsupported", EcrFailureKinds.UNSUPPORTED)
        assertEquals("NONE", EcrNextSteps.NONE)
        assertEquals(
            "INQUIRE_BY_MERCHANT_REFERENCE",
            EcrNextSteps.INQUIRE_BY_MERCHANT_REFERENCE,
        )
        assertEquals("kind", EcrFailureKeys.KIND)
        assertEquals("message", EcrFailureKeys.MESSAGE)
    }

    @Test
    fun `transaction keys are spelled exactly this way`() {
        assertEquals("transactionId", EcrTransactionKeys.TRANSACTION_ID)
        assertEquals("stan", EcrTransactionKeys.STAN)
        assertEquals("type", EcrTransactionKeys.TYPE)
        assertEquals("status", EcrTransactionKeys.STATUS)
        assertEquals("amount", EcrTransactionKeys.AMOUNT)
        assertEquals("totalAmount", EcrTransactionKeys.TOTAL_AMOUNT)
        assertEquals("currency", EcrTransactionKeys.CURRENCY)
        assertEquals("transactionTime", EcrTransactionKeys.TRANSACTION_TIME)
        assertEquals("maskedPan", EcrTransactionKeys.MASKED_PAN)
        assertEquals("cardHolderName", EcrTransactionKeys.CARD_HOLDER_NAME)
        assertEquals("rrn", EcrTransactionKeys.RRN)
        assertEquals("authCode", EcrTransactionKeys.AUTH_CODE)
        assertEquals("batchId", EcrTransactionKeys.BATCH_ID)
        assertEquals("terminalId", EcrTransactionKeys.TERMINAL_ID)
        assertEquals("isRefunded", EcrTransactionKeys.IS_REFUNDED)
        assertEquals("canVoid", EcrTransactionKeys.CAN_VOID)
        assertEquals("canRefund", EcrTransactionKeys.CAN_REFUND)
    }

    @Test
    fun `error codes and the channel name are spelled exactly this way`() {
        assertEquals("ecr_invalid_argument", EcrErrorCodes.INVALID_ARGUMENT)
        assertEquals("ecr_internal", EcrErrorCodes.INTERNAL)
        assertEquals("com.amwalpay.ecr/methods", ECR_METHOD_CHANNEL)
    }

    @Test
    fun `only the IP transports have a listener to reach`() {
        assertEquals(true, EcrTransports.isIpTransport("ethernet"))
        assertEquals(true, EcrTransports.isIpTransport("wifi"))
        assertEquals(false, EcrTransports.isIpTransport("bluetooth"))
        assertEquals(false, EcrTransports.isIpTransport("webService"))
        // A transport this build has not heard of is not an IP one either:
        // guessing would open a socket nothing is listening on.
        assertEquals(false, EcrTransports.isIpTransport("carrier-pigeon"))
        assertEquals(false, EcrTransports.isIpTransport(null))
    }
}
