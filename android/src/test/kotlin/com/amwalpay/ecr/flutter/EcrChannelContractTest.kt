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
        assertEquals("probeReachability", EcrMethods.PROBE_REACHABILITY)
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
        assertEquals("merchantReference", EcrArgs.MERCHANT_REFERENCE)
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
        assertEquals("merchantId", EcrConfigKeys.MERCHANT_ID)
        assertEquals("terminalId", EcrConfigKeys.TERMINAL_ID)
        assertEquals("environment", EcrConfigKeys.ENVIRONMENT)
    }

    @Test
    fun `result keys are spelled exactly this way`() {
        assertEquals("outcome", EcrResultKeys.OUTCOME)
        assertEquals("merchantReference", EcrResultKeys.MERCHANT_REFERENCE)
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
        assertEquals("partialApproval", EcrTransactionKeys.PARTIAL_APPROVAL)
        assertEquals("authorizedAmount", EcrTransactionKeys.AUTHORIZED_AMOUNT)
    }

    @Test
    fun `error codes and the channel name are spelled exactly this way`() {
        assertEquals("ecr_invalid_argument", EcrErrorCodes.INVALID_ARGUMENT)
        assertEquals("ecr_internal", EcrErrorCodes.INTERNAL)
        assertEquals("com.amwalpay.ecr/methods", ECR_METHOD_CHANNEL)
    }

    @Test
    fun `only Wi-Fi is an IP transport and USB cable is not`() {
        assertEquals(false, EcrTransports.isIpTransport("usb_cable"))
        assertEquals(true, EcrTransports.isIpTransport("wifi"))
        assertEquals(false, EcrTransports.isIpTransport("bluetooth"))
        assertEquals(false, EcrTransports.isIpTransport("webService"))
        assertEquals(true, EcrTransports.isWebService("webService"))
        assertEquals(true, EcrTransports.isWebService("web_service"))
        assertEquals(true, EcrTransports.isUsbCable("usb_cable"))
        assertEquals(false, EcrTransports.isUsbCable("wifi"))
        // A transport this build has not heard of is not an IP one either:
        // guessing would open a socket nothing is listening on.
        assertEquals(false, EcrTransports.isIpTransport("carrier-pigeon"))
        assertEquals(false, EcrTransports.isIpTransport(null))
    }

    @Test
    fun `Wi-Fi, USB cable and Web Service can be driven from the plugin`() {
        assertEquals(true, EcrTransports.isSupportedTransport("usb_cable"))
        assertEquals(true, EcrTransports.isSupportedTransport("wifi"))
        assertEquals(true, EcrTransports.isSupportedTransport("webService"))
        assertEquals(true, EcrTransports.isSupportedTransport("web_service"))
        assertEquals(false, EcrTransports.isSupportedTransport("bluetooth"))
        assertEquals(true, EcrTransports.supportsReceipt("wifi"))
        assertEquals(true, EcrTransports.supportsReceipt("usb_cable"))
        assertEquals(false, EcrTransports.supportsReceipt("webService"))
    }

    @Test
    fun `reachability keys are spelled exactly this way`() {
        assertEquals("reachable", EcrReachabilityKeys.REACHABLE)
        assertEquals("host", EcrReachabilityKeys.HOST)
        assertEquals("port", EcrReachabilityKeys.PORT)
        assertEquals("error", EcrReachabilityKeys.ERROR)
        assertEquals("endpoint", EcrReachabilityKeys.ENDPOINT)
    }
}
