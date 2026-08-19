package com.amwalpay.ecr.flutter

import com.amwalpay.ecr.EcrConfig
import com.amwalpay.ecr.EcrInquiry
import com.amwalpay.ecr.EcrReceipt
import com.amwalpay.ecr.EcrResult
import com.amwalpay.ecr.EcrTransaction
import com.amwalpay.ecr.Failure
import com.amwalpay.ecr.NextStep
import java.math.BigDecimal
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val KEY = "881dc200c9833da726e9376c2e32cff7"

/**
 * What the Android host does with the 1.0.4 additions.
 *
 * The mirror of the iOS host's `EcrReferenceAndSigningTests` and of the Dart
 * side's `reference_and_signing_test.dart`. All three assert the same things in
 * the same words, because "the two platforms behave the same" is a claim that
 * has to be checked on both sides rather than asserted in a document.
 *
 * This is the mapping, not the protocol: signing itself is the SDK's, and is
 * tested in `ecr-sdk/src/test/.../SecureHashTest.kt`. What matters here is that
 * nothing is dropped on the way across the channel.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class EcrReferenceAndSigningTest {

    /** Answers what it is told to, and remembers what it was asked. */
    private class SpyTerminal(
        var result: EcrResult = EcrResult.Failed("REQ", Failure.Timeout("no answer")),
        var inquiry: EcrInquiry = EcrInquiry.NotFound("REQ", "nothing", "{}"),
    ) : EcrTerminalPort {

        val calls = mutableListOf<String>()
        var config: EcrConfig? = null
        var lastMerchantReferenceId: String? = null
        var lastOriginalReference: String? = null
        var lastTransactionDate: String? = null

        override suspend fun isReachable(): Boolean = true

        override suspend fun sale(amount: BigDecimal, merchantReferenceId: String): EcrResult {
            calls += "sale"
            lastMerchantReferenceId = merchantReferenceId
            return result
        }

        override suspend fun void(
            receiptNumber: String,
            originalTerminalId: String,
            merchantReferenceId: String,
        ): EcrResult {
            calls += "void"
            lastMerchantReferenceId = merchantReferenceId
            return result
        }

        override suspend fun refund(
            amount: BigDecimal,
            receiptNumber: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReferenceId: String,
        ): EcrResult {
            calls += "refund"
            lastMerchantReferenceId = merchantReferenceId
            return result
        }

        override suspend fun inquire(
            receiptNumber: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReferenceId: String,
        ): EcrInquiry {
            calls += "inquire"
            lastMerchantReferenceId = merchantReferenceId
            return inquiry
        }

        override suspend fun inquireByReference(
            originalReference: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReferenceId: String,
        ): EcrInquiry {
            calls += "inquireByReference"
            lastOriginalReference = originalReference
            lastTransactionDate = transactionDate
            lastMerchantReferenceId = merchantReferenceId
            return inquiry
        }

        override suspend fun receipt(
            receiptNumber: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReferenceId: String,
        ): EcrReceipt {
            calls += "receipt"
            lastMerchantReferenceId = merchantReferenceId
            return EcrReceipt.Unavailable("REQ", "no", "{}")
        }
    }

    private class Recorder : EcrReply {
        val successes = mutableListOf<Any?>()
        val errors = mutableListOf<Pair<String, String?>>()

        override fun success(value: Any?) { successes += value }
        override fun error(code: String, message: String?) { errors += code to message }
        override fun notImplemented() = Unit

        @Suppress("UNCHECKED_CAST")
        fun result(): Map<String, Any?> =
            successes.filterIsInstance<Map<*, *>>().first() as Map<String, Any?>
    }

    private fun args(
        merchantReferenceId: String = "",
        originalMerchantReference: String = "",
        transactionDate: String = "",
        secureHashKey: String = "",
        autoInquireOnFailure: Boolean = true,
    ): Map<String, Any?> = mapOf(
        EcrArgs.OPERATION_ID to "op-1",
        EcrArgs.HOST to "192.168.1.50",
        EcrArgs.SERIAL_NUMBER to "P653200085189",
        EcrArgs.TRANSPORT to EcrTransports.WIFI,
        EcrArgs.CONFIG to mapOf(
            EcrConfigKeys.ECR_ID to "TILL7",
            EcrConfigKeys.CURRENCY_CODE to "512",
            EcrConfigKeys.MINOR_UNIT_DIGITS to 3,
            EcrConfigKeys.PORT to 9100,
            EcrConfigKeys.CONNECT_TIMEOUT_MS to 10_000,
            EcrConfigKeys.RESPONSE_TIMEOUT_MS to 120_000,
            EcrConfigKeys.PROBE_TIMEOUT_MS to 3_000,
            EcrConfigKeys.SECURE_HASH_KEY to secureHashKey,
            EcrConfigKeys.AUTO_INQUIRE_ON_FAILURE to autoInquireOnFailure,
        ),
        EcrArgs.AMOUNT to "1.234",
        EcrArgs.RECEIPT_NUMBER to "215",
        EcrArgs.TRANSACTION_DATE to transactionDate,
        EcrArgs.ORIGINAL_TERMINAL_ID to "",
        EcrArgs.MERCHANT_REFERENCE_ID to merchantReferenceId,
        EcrArgs.ORIGINAL_MERCHANT_REFERENCE to originalMerchantReference,
    )

    private fun handlerFor(terminal: SpyTerminal, scope: TestScope): EcrCallHandler =
        EcrCallHandler(scope) { _, _, config ->
            terminal.config = config
            terminal
        }

    // ── The shared secret ─────────────────────────────────────────────────

    @Test
    fun `the secret and the auto-inquire setting reach the SDK`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = SpyTerminal()

            handlerFor(terminal, this).handle(
                EcrMethods.SALE,
                args(secureHashKey = KEY, autoInquireOnFailure = false),
                Recorder(),
            )

            assertEquals(KEY, terminal.config?.secureHashKey)
            assertEquals(false, terminal.config?.autoInquireOnFailure)
        }

    @Test
    fun `an empty key means unsigned rather than missing`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = SpyTerminal()

            handlerFor(terminal, this).handle(EcrMethods.SALE, args(), Recorder())

            assertEquals("", terminal.config?.secureHashKey)
            // The default is on, and a host that was not told keeps it.
            assertEquals(true, terminal.config?.autoInquireOnFailure)
        }

    @Test
    fun `an unauthenticated answer crosses as its own kind, not as a decline`() =
        runTest(UnconfinedTestDispatcher()) {
            // The one reading that must never happen: a till that books this as
            // a refusal will retry, and the cardholder pays twice.
            val terminal = SpyTerminal(
                result = EcrResult.Failed(
                    "ORDER-1",
                    Failure.Unauthenticated("not signed with this terminal's key"),
                ),
            )
            val reply = Recorder()

            handlerFor(terminal, this).handle(EcrMethods.SALE, args(secureHashKey = KEY), reply)

            val map = reply.result()
            assertEquals(EcrOutcomes.FAILED, map[EcrResultKeys.OUTCOME])
            @Suppress("UNCHECKED_CAST")
            val failure = map[EcrResultKeys.FAILURE] as Map<String, Any?>
            assertEquals(EcrFailureKinds.UNAUTHENTICATED, failure[EcrFailureKeys.KIND])
        }

    // ── The till's own reference ──────────────────────────────────────────

    @Test
    fun `the reference is handed to the SDK and reported back`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = SpyTerminal(
                result = EcrResult.Approved(
                    merchantReferenceId = "ORDER-4471",
                    amount = "1.234",
                    responseCode = "00",
                    rrn = "622113155340",
                    authCode = "517842",
                    maskedPan = "543173xxxx5785",
                    partialApproval = false,
                    requestedAmount = "",
                    raw = "{}",
                ),
            )
            val reply = Recorder()

            handlerFor(terminal, this).handle(
                EcrMethods.SALE,
                args(merchantReferenceId = "ORDER-4471"),
                reply,
            )

            assertEquals("ORDER-4471", terminal.lastMerchantReferenceId)
            assertEquals("ORDER-4471", reply.result()[EcrResultKeys.MERCHANT_REFERENCE_ID])
        }

    @Test
    fun `every operation carries the reference`() = runTest(UnconfinedTestDispatcher()) {
        val methods = listOf(
            EcrMethods.SALE,
            EcrMethods.VOID,
            EcrMethods.REFUND,
            EcrMethods.INQUIRE,
            EcrMethods.RECEIPT,
        )

        for (method in methods) {
            val terminal = SpyTerminal()
            handlerFor(terminal, this).handle(
                method,
                args(merchantReferenceId = "REF-1"),
                Recorder(),
            )
            assertEquals("REF-1", terminal.lastMerchantReferenceId, method)
        }
    }

    // ── Looking a transaction up by its reference ─────────────────────────

    @Test
    fun `the lookup takes the original's reference, not this call's own`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = SpyTerminal()

            handlerFor(terminal, this).handle(
                EcrMethods.INQUIRE_BY_REFERENCE,
                args(merchantReferenceId = "LOOKUP-1", originalMerchantReference = "ORDER-4471"),
                Recorder(),
            )

            assertEquals(listOf("inquireByReference"), terminal.calls)
            assertEquals("ORDER-4471", terminal.lastOriginalReference)
            assertEquals("LOOKUP-1", terminal.lastMerchantReferenceId)
        }

    @Test
    fun `the lookup is refused without the reference it looks up`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = SpyTerminal()
            val reply = Recorder()

            handlerFor(terminal, this).handle(EcrMethods.INQUIRE_BY_REFERENCE, args(), reply)

            assertEquals(EcrErrorCodes.INVALID_ARGUMENT, reply.errors.single().first)
            assertTrue(terminal.calls.isEmpty(), "nothing may be sent")
        }

    // ── What the follow-up found ──────────────────────────────────────────

    @Test
    fun `a failure that was followed up carries what it found`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = SpyTerminal(
                result = EcrResult.Failed(
                    merchantReferenceId = "ORDER-4471",
                    failure = Failure.Timeout("no answer in 120s"),
                    recovered = EcrInquiry.Found("ORDER-4471", transaction("Approved"), "{}"),
                ),
            )
            val reply = Recorder()

            handlerFor(terminal, this).handle(EcrMethods.SALE, args(), reply)

            @Suppress("UNCHECKED_CAST")
            val recovered = reply.result()[EcrResultKeys.RECOVERED] as Map<String, Any?>
            assertEquals(EcrOutcomes.FOUND, recovered[EcrResultKeys.OUTCOME])
            @Suppress("UNCHECKED_CAST")
            val found = recovered[EcrResultKeys.TRANSACTION] as Map<String, Any?>
            assertEquals("Approved", found[EcrTransactionKeys.STATUS])
        }

    @Test
    fun `no follow-up means the key carries nothing rather than a failed lookup`() =
        runTest(UnconfinedTestDispatcher()) {
            // The Dart side reads absence as "no follow-up was made", which is
            // not the same as "the follow-up found nothing".
            val terminal = SpyTerminal(
                result = EcrResult.Failed("ORDER-4471", Failure.Timeout("no answer")),
            )
            val reply = Recorder()

            handlerFor(terminal, this).handle(
                EcrMethods.SALE,
                args(autoInquireOnFailure = false),
                reply,
            )

            assertNull(reply.result()[EcrResultKeys.RECOVERED])
        }

    // ── What the terminal says to do next ─────────────────────────────────

    @Test
    fun `a decline carries the step the terminal stated`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = SpyTerminal(
                result = EcrResult.Declined(
                    merchantReferenceId = "ORDER-1",
                    responseCode = "05",
                    reason = "Do not honour",
                    nextStep = NextStep.INQUIRE_BY_MERCHANT_REFERENCE,
                    raw = "{}",
                ),
            )
            val reply = Recorder()

            handlerFor(terminal, this).handle(EcrMethods.SALE, args(), reply)

            assertEquals(
                EcrNextSteps.INQUIRE_BY_MERCHANT_REFERENCE,
                reply.result()[EcrResultKeys.NEXT_STEP],
            )
        }

    @Test
    fun `an ordinary decline says nothing further is needed`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = SpyTerminal(
                result = EcrResult.Declined(
                    merchantReferenceId = "ORDER-1",
                    responseCode = "51",
                    reason = "Insufficient funds",
                    nextStep = NextStep.NONE,
                    raw = "{}",
                ),
            )
            val reply = Recorder()

            handlerFor(terminal, this).handle(EcrMethods.SALE, args(), reply)

            assertEquals(EcrNextSteps.NONE, reply.result()[EcrResultKeys.NEXT_STEP])
            assertFalse(reply.errors.isNotEmpty())
        }

    private fun transaction(status: String) = EcrTransaction(
        transactionId = "4471",
        stan = "000215",
        type = "Sale",
        status = status,
        amount = "1.234",
        totalAmount = "1.234",
        currency = "OMR",
        transactionTime = "2026-08-09T12:41:07",
        maskedPan = "543173xxxx5785",
        cardHolderName = "",
        rrn = "622113155340",
        authCode = "517842",
        batchId = "1",
        terminalId = "31629",
        isRefunded = false,
        canVoid = true,
        canRefund = true,
    )
}
