package com.amwalpay.ecr.flutter

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.time.Duration

/**
 * Asks the Amwal payment app on this device to print a receipt image after an
 * app-to-app result.
 *
 * Image width must be exactly [PRINTER_WIDTH] (384); height may be any positive
 * value; encoded size must not exceed [PRINTER_MAX_BYTES] (15 MiB). Answers
 * carry [EcrPrintStatus] via [EXTRA_STATUS] plus [EXTRA_MESSAGE] as separate
 * fields — never merged.
 *
 * Flutter owns the UI: nothing here toasts. The outcome comes back through
 * [PaymentAppPrintResults] to the call waiting on it.
 */
internal object PaymentAppPrint {

    private const val TAG = "AmwalEcrPrint"

    /**
     * Max printable bitmap width on Amwal POS (Topwise) printers.
     * Matches `pospresentation.Utils.viewToBitmap(layout, 384)`.
     */
    const val PRINTER_WIDTH = 384

    /** Max encoded image payload (PNG/JPEG bytes) accepted for PRINT. */
    const val PRINTER_MAX_BYTES = 15 * 1024 * 1024 // 15 MiB

    const val ACTION = "com.amwalpay.pos.ecr.PRINT"
    const val EXTRA_RECEIPT_IMAGE = "amwal.ecr.receiptImage"
    const val EXTRA_MERCHANT_REFERENCE = "amwal.ecr.merchantReference"
    const val EXTRA_OK = "amwal.ecr.printOk"
    const val EXTRA_STATUS = "amwal.ecr.printStatus"
    const val EXTRA_MESSAGE = "amwal.ecr.printMessage"
    const val REQUEST_CODE = 0x5052 // 'PR'

    /**
     * Starts PRINT and blocks until the payment app answers or [timeout] elapses.
     *
     * Safe to call from a background dispatcher (the Activity launch hops to
     * the main thread). Returns a failed outcome when the image is wrong, the
     * app is missing, or another print is already in flight — without starting
     * anything in those cases.
     */
    fun exchange(
        activity: Activity,
        results: PaymentAppPrintResults,
        merchantReference: String = "",
        imagePng: ByteArray,
        timeout: Duration,
    ): EcrPrintOutcome {
        val imageError = validatePrintImage(imagePng)
        if (imageError != null) {
            Log.w(TAG, imageError)
            return EcrPrintOutcome.failed(imageError)
        }
        val component = Intent(ACTION).setPackage(PaymentAppEcrChannel.PACKAGE_NAME)
            .resolveActivity(activity.packageManager)
        if (component == null) {
            return EcrPrintOutcome.failed(
                "The Amwal payment app is not installed, or does not accept PRINT",
            )
        }
        val waiting = results.claim()
            ?: return EcrPrintOutcome.failed("A print is already in progress")

        val intent = Intent(ACTION)
            .setComponent(component)
            .putExtra(EXTRA_MERCHANT_REFERENCE, merchantReference)
            .putExtra(EXTRA_RECEIPT_IMAGE, imagePng)
        Handler(Looper.getMainLooper()).post {
            try {
                activity.startActivityForResult(intent, REQUEST_CODE)
            } catch (e: Exception) {
                Log.e(TAG, "could not start PRINT", e)
                results.deliver(EcrPrintOutcome.failed(e.message ?: "could not start print"))
            }
        }

        return waiting.await(timeout)
            ?: EcrPrintOutcome.failed("The payment app did not answer the print request")
    }

    /**
     * Ensures the print payload is a decodable image with width exactly 384
     * and encoded size at most 15 MiB. Height may be any positive value.
     * Returns null when valid.
     *
     * PNG is checked from the IHDR (works in JVM unit tests without Android
     * graphics). JPEG and others fall back to [BitmapFactory].
     */
    fun validatePrintImage(imagePng: ByteArray?): String? {
        if (imagePng == null || imagePng.isEmpty()) {
            return "Print image is required (width must be ${PRINTER_WIDTH}px)"
        }
        if (imagePng.size > PRINTER_MAX_BYTES) {
            return "Print image size must not exceed " +
                "${PRINTER_MAX_BYTES / (1024 * 1024)} MB " +
                "(was ${imagePng.size} bytes)"
        }
        val pngSize = pngIhdrSize(imagePng)
        if (pngSize != null) {
            val (width, height) = pngSize
            if (width <= 0 || height <= 0) {
                return "Print image could not be decoded"
            }
            if (width != PRINTER_WIDTH) {
                return "Print image width must be ${PRINTER_WIDTH}px " +
                    "(was ${width}x$height)"
            }
            return null
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(imagePng, 0, imagePng.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            return "Print image could not be decoded"
        }
        if (bounds.outWidth != PRINTER_WIDTH) {
            return "Print image width must be ${PRINTER_WIDTH}px " +
                "(was ${bounds.outWidth}x${bounds.outHeight})"
        }
        return null
    }

    /** PNG IHDR width/height, or null when [bytes] is not a PNG. */
    internal fun pngIhdrSize(bytes: ByteArray): Pair<Int, Int>? {
        if (bytes.size < 24) return null
        if (bytes[0] != 0x89.toByte() || bytes[1] != 'P'.code.toByte() ||
            bytes[2] != 'N'.code.toByte() || bytes[3] != 'G'.code.toByte()
        ) {
            return null
        }
        fun be32(at: Int): Int =
            ((bytes[at].toInt() and 0xFF) shl 24) or
                ((bytes[at + 1].toInt() and 0xFF) shl 16) or
                ((bytes[at + 2].toInt() and 0xFF) shl 8) or
                (bytes[at + 3].toInt() and 0xFF)
        return be32(16) to be32(20)
    }
}

/**
 * Holds the one PRINT request that is with the payment app.
 *
 * One at a time, same reason as [PaymentAppResults]: the device has one
 * printer path and one cardholder. A second is refused rather than queued.
 */
internal class PaymentAppPrintResults : PluginRegistry.ActivityResultListener {

    private val busy = AtomicBoolean(false)
    private val handovers = ArrayBlockingQueue<EcrPrintOutcome>(1)

    /** Takes the slot, or null when it is already taken. */
    fun claim(): Waiting? {
        if (!busy.compareAndSet(false, true)) return null
        handovers.clear()
        return Waiting()
    }

    fun deliver(outcome: EcrPrintOutcome) {
        handovers.offer(outcome)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PaymentAppPrint.REQUEST_CODE) return false
        deliver(
            outcomeFor(
                resultCode = resultCode,
                ok = data?.getBooleanExtra(
                    PaymentAppPrint.EXTRA_OK,
                    resultCode == Activity.RESULT_OK,
                ),
                statusWire = data?.getStringExtra(PaymentAppPrint.EXTRA_STATUS),
                message = data?.getStringExtra(PaymentAppPrint.EXTRA_MESSAGE).orEmpty(),
            ),
        )
        return true
    }

    /** What a PRINT result means — apart from [Intent] so it can be tested. */
    internal fun outcomeFor(
        resultCode: Int,
        ok: Boolean?,
        statusWire: String?,
        message: String,
    ): EcrPrintOutcome = EcrPrintOutcome.from(
        ok = ok ?: (resultCode == Activity.RESULT_OK),
        message = message,
        statusWire = statusWire,
    )

    inner class Waiting {
        fun await(timeout: Duration): EcrPrintOutcome? = try {
            handovers.poll(timeout.inWholeMilliseconds, TimeUnit.MILLISECONDS)
        } finally {
            busy.set(false)
        }
    }
}
