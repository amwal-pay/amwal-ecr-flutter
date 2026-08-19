package com.amwalpay.ecr.flutter

import com.amwalpay.ecr.EcrConfig
import com.amwalpay.ecr.EcrInquiry
import com.amwalpay.ecr.EcrReceipt
import com.amwalpay.ecr.EcrResult
import com.amwalpay.ecr.EcrTransaction
import com.amwalpay.ecr.Failure
import com.amwalpay.ecr.NextStep
import java.math.BigDecimal
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * What the Android host does with a call.
 *
 * The two things worth testing here are not values but counts: that a request
 * is sent once and only once, and that a call is answered once and only once.
 * A wrapper that gets a field wrong prints a bad receipt; a wrapper that sends
 * a sale twice takes the money twice.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class EcrCallHandlerTest {

    /** Records what it was asked, and answers what it was told to. */
    private class FakeTerminal(
        var reachable: Boolean = true,
        var result: EcrResult = approved(),
        var inquiry: EcrInquiry = EcrInquiry.NotFound("REQ", "nothing", "{}"),
        var receipt: EcrReceipt = EcrReceipt.Unavailable("REQ", "nothing", "{}"),
        /** Held open so a test can cancel while the terminal has the request. */
        var gate: CompletableDeferred<Unit>? = null,
    ) : EcrTerminalPort {

        val calls = mutableListOf<String>()
        var lastAmount: BigDecimal? = null
        var lastReceiptNumber: String? = null
        var lastTransactionDate: String? = null
        var lastOriginalTerminalId: String? = null
        var lastMerchantReferenceId: String? = null
        var lastOriginalReference: String? = null

        private suspend fun waitIfHeld() {
            gate?.await()
        }

        override suspend fun isReachable(): Boolean {
            calls += "isReachable"
            waitIfHeld()
            return reachable
        }

        override suspend fun sale(amount: BigDecimal, merchantReferenceId: String): EcrResult {
            calls += "sale"
            lastAmount = amount
            lastMerchantReferenceId = merchantReferenceId
            waitIfHeld()
            return result
        }

        override suspend fun void(
            receiptNumber: String,
            originalTerminalId: String,
            merchantReferenceId: String,
        ): EcrResult {
            calls += "void"
            lastReceiptNumber = receiptNumber
            lastOriginalTerminalId = originalTerminalId
            lastMerchantReferenceId = merchantReferenceId
            waitIfHeld()
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
            lastAmount = amount
            lastReceiptNumber = receiptNumber
            lastTransactionDate = transactionDate
            lastOriginalTerminalId = originalTerminalId
            lastMerchantReferenceId = merchantReferenceId
            waitIfHeld()
            return result
        }

        override suspend fun inquire(
            receiptNumber: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReferenceId: String,
        ): EcrInquiry {
            calls += "inquire"
            lastReceiptNumber = receiptNumber
            lastTransactionDate = transactionDate
            lastMerchantReferenceId = merchantReferenceId
            waitIfHeld()
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
            waitIfHeld()
            return inquiry
        }

        override suspend fun receipt(
            receiptNumber: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReferenceId: String,
        ): EcrReceipt {
            calls += "receipt"
            lastReceiptNumber = receiptNumber
            lastTransactionDate = transactionDate
            lastMerchantReferenceId = merchantReferenceId
            waitIfHeld()
            return receipt
        }

        companion object {
            fun approved(): EcrResult = EcrResult.Approved(
                merchantReferenceId = "A1B2C3D4E5F6",
                amount = "1.234",
                responseCode = "00",
                rrn = "622113155340",
                authCode = "517842",
                maskedPan = "543173xxxx5785",
                partialApproval = false,
                requestedAmount = "",
                raw = "{}",
            )
        }
    }

    /** Records every answer, so a second one is visible rather than lost. */
    private class RecordingReply : EcrReply {
        val successes = mutableListOf<Any?>()
        val errors = mutableListOf<Pair<String, String?>>()
        var notImplementedCount = 0

        override fun success(value: Any?) { successes += value }
        override fun error(code: String, message: String?) { errors += code to message }
        override fun notImplemented() { notImplementedCount++ }

        /** How many times this call was answered. Must never exceed one. */
        val answerCount: Int get() = successes.size + errors.size + notImplementedCount

        @Suppress("UNCHECKED_CAST")
        fun result(): Map<String, Any?> = successes.single() as Map<String, Any?>
    }

    private fun args(
        operationId: String = "op-1",
        host: String = "192.168.1.50",
        transport: String = "wifi",
        amount: String? = "1.234",
        receiptNumber: String = "",
        transactionDate: String = "",
        originalTerminalId: String = "",
    ): Map<String, Any?> = mapOf(
        EcrArgs.OPERATION_ID to operationId,
        EcrArgs.HOST to host,
        EcrArgs.SERIAL_NUMBER to "P653200085189",
        EcrArgs.TRANSPORT to transport,
        EcrArgs.CONFIG to mapOf(
            EcrConfigKeys.ECR_ID to "TILL7",
            EcrConfigKeys.CURRENCY_CODE to "512",
            EcrConfigKeys.MINOR_UNIT_DIGITS to 3,
            EcrConfigKeys.PORT to 9100,
            EcrConfigKeys.CONNECT_TIMEOUT_MS to 10_000,
            EcrConfigKeys.RESPONSE_TIMEOUT_MS to 120_000,
            EcrConfigKeys.PROBE_TIMEOUT_MS to 3_000,
        ),
        EcrArgs.AMOUNT to amount,
        EcrArgs.RECEIPT_NUMBER to receiptNumber,
        EcrArgs.TRANSACTION_DATE to transactionDate,
        EcrArgs.ORIGINAL_TERMINAL_ID to originalTerminalId,
    )

    private fun handlerFor(terminal: EcrTerminalPort, scope: TestScope): EcrCallHandler =
        EcrCallHandler(scope) { _, _, _ -> terminal }

    @Test
    fun `a sale is sent once and answered once`() = runTest(UnconfinedTestDispatcher()) {
        val terminal = FakeTerminal()
        val reply = RecordingReply()

        handlerFor(terminal, this).handle(EcrMethods.SALE, args(), reply)

        assertEquals(listOf("sale"), terminal.calls)
        assertEquals(1, reply.answerCount)
        assertEquals(EcrOutcomes.APPROVED, reply.result()[EcrResultKeys.OUTCOME])
    }

    @Test
    fun `the amount arrives as an exact decimal, not a double`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal()

            handlerFor(terminal, this)
                .handle(EcrMethods.SALE, args(amount = "1.234"), RecordingReply())

            // BigDecimal("1.234"), not 1.2339999999999999857891452847979962825775
            assertEquals(BigDecimal("1.234"), terminal.lastAmount)
        }

    @Test
    fun `an amount that is not a decimal is refused before anything is sent`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal()
            val reply = RecordingReply()

            handlerFor(terminal, this).handle(EcrMethods.SALE, args(amount = "1,234"), reply)

            assertTrue(terminal.calls.isEmpty())
            assertEquals(1, reply.answerCount)
            assertEquals(EcrErrorCodes.INVALID_ARGUMENT, reply.errors.single().first)
        }

    @Test
    fun `a sale with no amount is refused before anything is sent`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal()
            val reply = RecordingReply()

            handlerFor(terminal, this).handle(EcrMethods.SALE, args(amount = null), reply)

            assertTrue(terminal.calls.isEmpty())
            assertEquals(EcrErrorCodes.INVALID_ARGUMENT, reply.errors.single().first)
        }

    @Test
    fun `a void carries the receipt number and the other terminal`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal()

            handlerFor(terminal, this).handle(
                EcrMethods.VOID,
                args(amount = null, receiptNumber = "215", originalTerminalId = "31629"),
                RecordingReply(),
            )

            assertEquals("215", terminal.lastReceiptNumber)
            assertEquals("31629", terminal.lastOriginalTerminalId)
        }

    @Test
    fun `a void with no receipt number is refused before anything is sent`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal()
            val reply = RecordingReply()

            handlerFor(terminal, this).handle(
                EcrMethods.VOID,
                args(amount = null, receiptNumber = "   "),
                reply,
            )

            assertTrue(terminal.calls.isEmpty())
            assertEquals(EcrErrorCodes.INVALID_ARGUMENT, reply.errors.single().first)
        }

    @Test
    fun `a refund carries amount, receipt number and the original day`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal()

            handlerFor(terminal, this).handle(
                EcrMethods.REFUND,
                args(amount = "0.216", receiptNumber = "208", transactionDate = "20260809"),
                RecordingReply(),
            )

            assertEquals(BigDecimal("0.216"), terminal.lastAmount)
            assertEquals("208", terminal.lastReceiptNumber)
            assertEquals("20260809", terminal.lastTransactionDate)
        }

    @Test
    fun `a transport with no listener is refused without touching the terminal`() =
        runTest(UnconfinedTestDispatcher()) {
            for (transport in listOf("bluetooth", "webService")) {
                val terminal = FakeTerminal()
                val reply = RecordingReply()

                handlerFor(terminal, this).handle(
                    EcrMethods.SALE,
                    args(transport = transport),
                    reply,
                )

                assertTrue(terminal.calls.isEmpty(), transport)
                assertEquals(1, reply.answerCount)
                val failure = reply.result()[EcrResultKeys.FAILURE] as Map<*, *>
                assertEquals(EcrFailureKinds.UNSUPPORTED, failure[EcrFailureKeys.KIND])
            }
        }

    @Test
    fun `isReachable over a transport with no listener is false, not a probe`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal()
            val reply = RecordingReply()

            handlerFor(terminal, this).handle(
                EcrMethods.IS_REACHABLE,
                args(transport = "bluetooth"),
                reply,
            )

            assertTrue(terminal.calls.isEmpty())
            assertEquals(false, reply.successes.single())
        }

    @Test
    fun `an unknown method is reported as not implemented, once`() =
        runTest(UnconfinedTestDispatcher()) {
            val reply = RecordingReply()

            handlerFor(FakeTerminal(), this).handle("teleport", args(), reply)

            assertEquals(1, reply.notImplementedCount)
            assertEquals(1, reply.answerCount)
        }

    @Test
    fun `a call with no arguments is refused rather than crashing`() =
        runTest(UnconfinedTestDispatcher()) {
            val reply = RecordingReply()

            handlerFor(FakeTerminal(), this).handle(EcrMethods.SALE, null, reply)

            assertEquals(EcrErrorCodes.INVALID_ARGUMENT, reply.errors.single().first)
        }

    @Test
    fun `a terminal that throws is an internal error, never a decline`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = object : EcrTerminalPort by FakeTerminal() {
                override suspend fun sale(
                    amount: BigDecimal,
                    merchantReferenceId: String,
                ): EcrResult =
                    throw IllegalStateException("the SDK fell over")
            }
            val reply = RecordingReply()

            handlerFor(terminal, this).handle(EcrMethods.SALE, args(), reply)

            // A decline would tell the till money did not move, which is not
            // something this side knows.
            assertEquals(1, reply.answerCount)
            assertEquals(EcrErrorCodes.INTERNAL, reply.errors.single().first)
        }

    @Test
    fun `cancelling names the operation and answers it as cancelled`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal(gate = CompletableDeferred())
            val handler = handlerFor(terminal, this)
            val reply = RecordingReply()

            handler.handle(EcrMethods.SALE, args(operationId = "till-9"), reply)
            assertEquals(1, handler.inFlightCount)

            val cancelReply = RecordingReply()
            handler.handle(
                EcrMethods.CANCEL,
                mapOf(EcrArgs.OPERATION_ID to "till-9"),
                cancelReply,
            )

            assertEquals(true, cancelReply.successes.single())
            assertEquals(1, reply.answerCount)
            val failure = reply.result()[EcrResultKeys.FAILURE] as Map<*, *>
            assertEquals(EcrFailureKinds.CANCELLED, failure[EcrFailureKeys.KIND])
            assertTrue(
                (failure[EcrFailureKeys.MESSAGE] as String).contains("inquire before retrying"),
            )

            // The terminal answers late. The call has already been answered, so
            // the reply is dropped rather than delivered a second time.
            terminal.gate!!.complete(Unit)
            assertEquals(1, reply.answerCount)
            // And nothing was sent again.
            assertEquals(listOf("sale"), terminal.calls)
        }

    @Test
    fun `cancelling an operation that already answered says nothing was running`() =
        runTest(UnconfinedTestDispatcher()) {
            val handler = handlerFor(FakeTerminal(), this)
            handler.handle(EcrMethods.SALE, args(operationId = "till-9"), RecordingReply())

            val reply = RecordingReply()
            handler.handle(EcrMethods.CANCEL, mapOf(EcrArgs.OPERATION_ID to "till-9"), reply)

            assertEquals(false, reply.successes.single())
        }

    @Test
    fun `an operation is deregistered once it answers`() =
        runTest(UnconfinedTestDispatcher()) {
            val handler = handlerFor(FakeTerminal(), this)

            handler.handle(EcrMethods.SALE, args(), RecordingReply())

            assertEquals(0, handler.inFlightCount)
        }

    @Test
    fun `a late answer after a cancel cannot answer the call twice`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal(gate = CompletableDeferred())
            val handler = handlerFor(terminal, this)
            val reply = RecordingReply()

            handler.handle(EcrMethods.SALE, args(operationId = "till-9"), reply)
            handler.handle(
                EcrMethods.CANCEL,
                mapOf(EcrArgs.OPERATION_ID to "till-9"),
                RecordingReply(),
            )
            terminal.gate!!.complete(Unit)

            assertEquals(1, reply.answerCount)
        }

    @Test
    fun `a declined sale is reported as declined, with the terminal's words`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal(
                result = EcrResult.Declined("REQ", "51", "Insufficient funds", NextStep.NONE, "{}"),
            )
            val reply = RecordingReply()

            handlerFor(terminal, this).handle(EcrMethods.SALE, args(), reply)

            val result = reply.result()
            assertEquals(EcrOutcomes.DECLINED, result[EcrResultKeys.OUTCOME])
            assertEquals("51", result[EcrResultKeys.RESPONSE_CODE])
            assertEquals("Insufficient funds", result[EcrResultKeys.REASON])
        }

    @Test
    fun `a timeout is reported as a failure, never as a decline`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal(
                result = EcrResult.Failed("REQ", Failure.Timeout("no answer in 120s")),
            )
            val reply = RecordingReply()

            handlerFor(terminal, this).handle(EcrMethods.SALE, args(), reply)

            val result = reply.result()
            assertEquals(EcrOutcomes.FAILED, result[EcrResultKeys.OUTCOME])
            val failure = result[EcrResultKeys.FAILURE] as Map<*, *>
            assertEquals(EcrFailureKinds.TIMEOUT, failure[EcrFailureKeys.KIND])
        }

    @Test
    fun `an inquiry answers with its own shape, not a sale's`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal(
                inquiry = EcrInquiry.Found(
                    merchantReferenceId = "REQ",
                    transaction = EcrTransaction(
                        transactionId = "e970c800",
                        stan = "000208",
                        type = "Purchase",
                        status = "Approved",
                        amount = "0.258",
                        totalAmount = "0.258",
                        currency = "OMR",
                        transactionTime = "2026-08-09T16:58:16",
                        maskedPan = "543173******5785",
                        cardHolderName = "",
                        rrn = "78628029647",
                        authCode = "",
                        batchId = "00000003",
                        terminalId = "31629",
                        isRefunded = false,
                        canVoid = true,
                        canRefund = true,
                    ),
                    raw = "{}",
                ),
            )
            val reply = RecordingReply()

            handlerFor(terminal, this).handle(
                EcrMethods.INQUIRE,
                args(amount = null, receiptNumber = "208", transactionDate = "20260809"),
                reply,
            )

            val result = reply.result()
            assertEquals(EcrOutcomes.FOUND, result[EcrResultKeys.OUTCOME])
            val transaction = result[EcrResultKeys.TRANSACTION] as Map<*, *>
            assertEquals("000208", transaction[EcrTransactionKeys.STAN])
            assertEquals("Approved", transaction[EcrTransactionKeys.STATUS])
            assertEquals(true, transaction[EcrTransactionKeys.CAN_VOID])
        }

    @Test
    fun `a receipt answers with its own shape too`() =
        runTest(UnconfinedTestDispatcher()) {
            val terminal = FakeTerminal(
                receipt = EcrReceipt.Ready("REQ", "https://example.test/r/1", "{}"),
            )
            val reply = RecordingReply()

            handlerFor(terminal, this).handle(
                EcrMethods.RECEIPT,
                args(amount = null, receiptNumber = "215", transactionDate = "20260809"),
                reply,
            )

            val result = reply.result()
            assertEquals(EcrOutcomes.READY, result[EcrResultKeys.OUTCOME])
            assertEquals("https://example.test/r/1", result[EcrResultKeys.URL])
        }

    @Test
    fun `nothing is ever sent twice, whatever the outcome`() =
        runTest(UnconfinedTestDispatcher()) {
            val outcomes = listOf(
                FakeTerminal.approved(),
                EcrResult.Declined("REQ", "51", "no", NextStep.NONE, "{}"),
                EcrResult.Failed("REQ", Failure.Timeout("no answer")),
                EcrResult.Failed("REQ", Failure.Unreachable("no route")),
                EcrResult.Failed("REQ", Failure.ConnectionLost("closed")),
                EcrResult.Failed("REQ", Failure.Malformed("not JSON")),
            )

            for (outcome in outcomes) {
                val terminal = FakeTerminal(result = outcome)
                val reply = RecordingReply()

                handlerFor(terminal, this).handle(EcrMethods.SALE, args(), reply)

                assertEquals(listOf("sale"), terminal.calls, outcome.toString())
                assertEquals(1, reply.answerCount, outcome.toString())
            }
        }
}

/** The default `EcrConfig` is read from the channel, not assumed. */
class EcrConfigMappingTest {

    @Test
    fun `every config field crosses, with milliseconds becoming Durations`() {
        val config = EcrMapping.config(
            mapOf(
                EcrConfigKeys.ECR_ID to "TILL7",
                EcrConfigKeys.CURRENCY_CODE to "840",
                EcrConfigKeys.MINOR_UNIT_DIGITS to 2,
                EcrConfigKeys.PORT to 9200,
                EcrConfigKeys.CONNECT_TIMEOUT_MS to 5_000,
                EcrConfigKeys.RESPONSE_TIMEOUT_MS to 90_000,
                EcrConfigKeys.PROBE_TIMEOUT_MS to 1_500,
            ),
        )

        assertEquals("TILL7", config.ecrId)
        assertEquals("840", config.currencyCode)
        assertEquals(2, config.minorUnitDigits)
        assertEquals(9200, config.port)
        assertEquals(5_000, config.connectTimeout.inWholeMilliseconds)
        assertEquals(90_000, config.responseTimeout.inWholeMilliseconds)
        assertEquals(1_500, config.probeTimeout.inWholeMilliseconds)
    }

    @Test
    fun `a missing config falls back to the SDK's own defaults`() {
        val defaults = EcrConfig()
        val config = EcrMapping.config(null)

        // A Dart side that gains a setting this host was not rebuilt for keeps
        // working rather than failing on an unknown key.
        assertEquals(defaults.ecrId, config.ecrId)
        assertEquals(defaults.port, config.port)
        assertEquals(defaults.minorUnitDigits, config.minorUnitDigits)
        assertEquals(defaults.responseTimeout, config.responseTimeout)
    }

    @Test
    fun `an amount crosses as text and is read exactly`() {
        assertEquals(BigDecimal("1.234"), EcrMapping.amount("1.234"))
        assertEquals(BigDecimal("0.000"), EcrMapping.amount("0.000"))
        assertNull(EcrMapping.amount(null))
        assertNull(EcrMapping.amount(""))
    }

    @Test
    fun `a failure maps to its channel kind`() {
        assertEquals(
            EcrFailureKinds.UNREACHABLE,
            EcrMapping.failure(Failure.Unreachable("x"))[EcrFailureKeys.KIND],
        )
        assertEquals(
            EcrFailureKinds.TIMEOUT,
            EcrMapping.failure(Failure.Timeout("x"))[EcrFailureKeys.KIND],
        )
        assertEquals(
            EcrFailureKinds.MALFORMED,
            EcrMapping.failure(Failure.Malformed("x"))[EcrFailureKeys.KIND],
        )
        assertEquals(
            EcrFailureKinds.CONNECTION_LOST,
            EcrMapping.failure(Failure.ConnectionLost("x"))[EcrFailureKeys.KIND],
        )
    }

    @Test
    fun `a one-shot reply lets the first answer through and drops the rest`() {
        var successes = 0
        var errors = 0
        val reply = OneShotReply(object : EcrReply {
            override fun success(value: Any?) { successes++ }
            override fun error(code: String, message: String?) { errors++ }
            override fun notImplemented() {}
        })

        reply.success("first")
        reply.success("second")
        reply.error("code", "message")

        assertEquals(1, successes)
        assertEquals(0, errors)
        assertTrue(reply.hasAnswered)
    }

    @Test
    fun `a one-shot reply that errored first stays errored`() {
        var successes = 0
        var errors = 0
        val reply = OneShotReply(object : EcrReply {
            override fun success(value: Any?) { successes++ }
            override fun error(code: String, message: String?) { errors++ }
            override fun notImplemented() {}
        })

        reply.error("code", "message")
        reply.success("late")

        assertEquals(1, errors)
        assertEquals(0, successes)
        assertFalse(successes > 0)
    }
}
