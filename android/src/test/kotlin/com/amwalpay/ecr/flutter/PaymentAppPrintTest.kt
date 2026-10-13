package com.amwalpay.ecr.flutter

import android.app.Activity
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds

class PaymentAppPrintTest {

    @Test
    fun `empty image is rejected`() {
        assertNotNull(PaymentAppPrint.validatePrintImage(null))
        assertNotNull(PaymentAppPrint.validatePrintImage(ByteArray(0)))
    }

    @Test
    fun `wrong width is rejected`() {
        val error = PaymentAppPrint.validatePrintImage(pngOfWidth(200, height = 40))
        assertNotNull(error)
        assertTrue(error!!.contains("384"))
        assertTrue(error.contains("200"))
    }

    @Test
    fun `384-wide image is accepted`() {
        assertNull(PaymentAppPrint.validatePrintImage(pngOfWidth(384, height = 80)))
    }

    @Test
    fun `image larger than 15 MB is rejected`() {
        val oversized = ByteArray(PaymentAppPrint.PRINTER_MAX_BYTES + 1)
        // Minimal PNG signature so size is checked before decode.
        oversized[0] = 0x89.toByte()
        oversized[1] = 'P'.code.toByte()
        oversized[2] = 'N'.code.toByte()
        oversized[3] = 'G'.code.toByte()
        val error = PaymentAppPrint.validatePrintImage(oversized)
        assertNotNull(error)
        assertTrue(error!!.contains("15 MB"))
    }

    @Test
    fun `outcome keeps status and message separate`() {
        val outcome = EcrPrintOutcome.from(
            ok = false,
            message = "printer jammed",
            statusWire = "FAILED",
        )
        assertEquals(EcrPrintStatus.FAILED, outcome.status)
        assertEquals("printer jammed", outcome.message)
        assertFalse(outcome.message.contains("FAILED"))

        val map = outcome.toChannelMap()
        assertEquals("FAILED", map[EcrPrintKeys.STATUS])
        assertEquals("printer jammed", map[EcrPrintKeys.MESSAGE])
        assertEquals(false, map[EcrPrintKeys.OK])
    }

    @Test
    fun `activity result delivers separate status and message`() {
        val results = PaymentAppPrintResults()
        val waiting = assertNotNull(results.claim())

        results.deliver(
            results.outcomeFor(
                resultCode = Activity.RESULT_OK,
                ok = true,
                statusWire = "SUCCESSFUL",
                message = "ok",
            ),
        )

        val outcome = assertNotNull(waiting.await(200.milliseconds))
        assertEquals(EcrPrintStatus.SUCCESSFUL, outcome.status)
        assertEquals("ok", outcome.message)
    }

    /** Minimal PNG with a real IHDR so width validation needs no Android graphics. */
    private fun pngOfWidth(width: Int, height: Int): ByteArray {
        val out = ByteArray(33)
        // Signature
        out[0] = 0x89.toByte()
        out[1] = 'P'.code.toByte()
        out[2] = 'N'.code.toByte()
        out[3] = 'G'.code.toByte()
        out[4] = 0x0D
        out[5] = 0x0A
        out[6] = 0x1A
        out[7] = 0x0A
        // IHDR length = 13
        out[11] = 13
        out[12] = 'I'.code.toByte()
        out[13] = 'H'.code.toByte()
        out[14] = 'D'.code.toByte()
        out[15] = 'R'.code.toByte()
        fun putBe32(at: Int, value: Int) {
            out[at] = ((value ushr 24) and 0xFF).toByte()
            out[at + 1] = ((value ushr 16) and 0xFF).toByte()
            out[at + 2] = ((value ushr 8) and 0xFF).toByte()
            out[at + 3] = (value and 0xFF).toByte()
        }
        putBe32(16, width)
        putBe32(20, height)
        out[24] = 8 // bit depth
        out[25] = 2 // colour type RGB
        return out
    }
}
