package com.amwalpay.ecr.flutter

import android.app.Activity
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds

/**
 * The payment app is another app: it can answer, answer late, answer with
 * nothing, or be killed before it answers at all. Each of those means
 * something different to a till standing in front of a cardholder, and these
 * pin down which is which.
 */
class PaymentAppResultsTest {

    @Test
    fun `an answer reaches the exchange waiting for it`() {
        val results = PaymentAppResults()
        val waiting = assertNotNull(results.claim())

        results.deliver(
            results.answerFor(Activity.RESULT_OK, """{"responseCode":"00"}"""),
        )

        val answer = assertIs<PaymentAppAnswer.Body>(waiting.await(200.milliseconds))
        assertEquals("""{"responseCode":"00"}""", String(answer.bytes))
    }

    @Test
    fun `a cancelled result is an unknown outcome, not a decline`() {
        val results = PaymentAppResults()

        // The payment app was destroyed before it could answer. The money may
        // well have moved, so the till is sent to inquire rather than retry.
        val answer = assertIs<PaymentAppAnswer.Interrupted>(
            results.answerFor(Activity.RESULT_CANCELED, null),
        )
        assertTrue(answer.reason.contains("inquire by merchant reference"))
    }

    @Test
    fun `an answer with an empty body is an unknown outcome too`() {
        val results = PaymentAppResults()
        assertIs<PaymentAppAnswer.Interrupted>(
            results.answerFor(Activity.RESULT_OK, ""),
        )
    }

    @Test
    fun `a body is read as the answer whatever the result code says`() {
        val results = PaymentAppResults()
        // A signed answer is a signed answer. Reading the code first would
        // turn a real decline into "unknown" and send a till reconciling
        // something it was already told about.
        assertIs<PaymentAppAnswer.Body>(
            results.answerFor(Activity.RESULT_CANCELED, """{"responseCode":"51"}"""),
        )
    }

    @Test
    fun `nothing at all is a timeout, and the slot is released`() {
        val results = PaymentAppResults()
        val waiting = assertNotNull(results.claim())

        assertNull(waiting.await(50.milliseconds))

        // Released, or a till that timed out once could never send again.
        assertNotNull(results.claim())
    }

    @Test
    fun `a second request while one is with the payment app is refused`() {
        val results = PaymentAppResults()
        assertNotNull(results.claim())

        // The device has one screen and one cardholder. "Busy" is something a
        // till can act on; being queued behind a payment it cannot see is not.
        assertNull(results.claim())
    }

    @Test
    fun `an answer arriving after the caller gave up is dropped, not delivered`() {
        val results = PaymentAppResults()
        val waiting = assertNotNull(results.claim())
        assertNull(waiting.await(50.milliseconds))

        results.deliver(
            results.answerFor(Activity.RESULT_OK, """{"responseCode":"00"}"""),
        )

        // The next request must not be handed the previous one's answer.
        val next = assertNotNull(results.claim())
        assertNull(next.await(50.milliseconds))
    }
}
