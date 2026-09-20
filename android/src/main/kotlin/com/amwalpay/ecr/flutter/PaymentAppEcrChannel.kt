package com.amwalpay.ecr.flutter

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import com.amwalpay.ecr.EcrChannel
import com.amwalpay.ecr.EcrChannelTimeout
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.time.Duration

/**
 * Carries one request to the Amwal payment app on this same device, and brings
 * one answer back.
 *
 * A channel and nothing more, the same as the USB one beside it: the request
 * arrives already signed and the answer is verified by [EcrTerminal], so
 * nothing here decides what a response code means. What is different is only
 * that the "wire" is an Activity result — there is no socket to open, no
 * address to dial, and the other end is an app rather than a device.
 *
 * Blocking on purpose. [EcrChannel.exchange] is called from a background
 * dispatcher, so waiting there is what the interface asks for; the result
 * arrives on the main thread and is handed over through a queue.
 */
internal class PaymentAppEcrChannel(
    private val packageName: String,
    private val activities: () -> Activity?,
    private val results: PaymentAppResults,
    private val log: (String) -> Unit = {},
) : EcrChannel {

    override val endpoint: String get() = packageName

    override val host: String get() = packageName

    /** No port: the terminal is this device. */
    override val port: Int get() = 0

    /**
     * Whether the payment app is installed and will accept a request.
     *
     * Deliberately launches nothing. A till checks this before it has an
     * amount, and putting the payment app on screen to find out would be worse
     * than not asking — the operator would be staring at a payment screen
     * nobody asked for.
     *
     * It cannot report whether a merchant is signed in or whether TMS permits
     * the operation. Both are answered by the payment app itself, in the
     * refusal to a real request or to a sign-on.
     */
    override fun probe(timeout: Duration): String? {
        val activity = activities()
            ?: return "There is no foreground Activity to start the payment app from"
        val resolved = resolve(activity)
            ?: return if (isInstalled(activity)) {
                "$packageName is installed but does not accept ECR requests — " +
                    "it may be a build from before app-to-app was added"
            } else {
                "The Amwal payment app ($packageName) is not installed on this device"
            }
        log("payment app resolved to ${resolved.flattenToShortString()}")
        return null
    }

    override fun exchange(body: ByteArray, timeout: Duration): ByteArray {
        val activity = activities()
            ?: throw IOException(
                "There is no foreground Activity to start the payment app from",
            )
        val component = resolve(activity)
            ?: throw IOException(
                "The Amwal payment app ($packageName) is not installed on this " +
                    "device, or does not accept ECR requests",
            )

        val waiting = results.claim()
            ?: throw IOException(
                "The payment app is already handling a request from this till",
            )

        val intent = Intent(ACTION)
            .setComponent(component)
            .putExtra(EXTRA_REQUEST, String(body, Charsets.UTF_8))
            .putExtra(EXTRA_PROTOCOL_VERSION, PROTOCOL_VERSION)
            .putExtra(EXTRA_TIMEOUT_MS, timeout.inWholeMilliseconds)

        // Started from the main thread: Android is strict about where an
        // Activity may be launched from, and this call arrives on an IO one.
        Handler(Looper.getMainLooper()).post {
            try {
                activity.startActivityForResult(intent, REQUEST_CODE)
            } catch (e: Exception) {
                results.deliver(PaymentAppAnswer.Broken(e.message ?: "could not start"))
            }
        }

        return when (val answer = waiting.await(timeout)) {
            is PaymentAppAnswer.Body -> answer.bytes
            is PaymentAppAnswer.Interrupted -> throw PaymentAppInterrupted(answer.reason)
            is PaymentAppAnswer.Broken -> throw IOException(answer.reason)
            null -> throw EcrChannelTimeout(
                "The payment app did not answer within $timeout",
            )
        }
    }

    private fun resolve(activity: Activity) =
        Intent(ACTION).setPackage(packageName)
            .resolveActivity(activity.packageManager)

    private fun isInstalled(activity: Activity): Boolean = try {
        activity.packageManager.getPackageInfo(packageName, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    internal companion object {
        /** Mirrored in the payment app's `EcrAppToAppActivity`. */
        const val ACTION = "com.amwalpay.pos.ecr.TRANSACTION"
        const val EXTRA_REQUEST = "amwal.ecr.request"
        const val EXTRA_PROTOCOL_VERSION = "amwal.ecr.protocolVersion"
        const val EXTRA_TIMEOUT_MS = "amwal.ecr.timeoutMs"
        const val EXTRA_RESPONSE = "amwal.ecr.response"
        const val PROTOCOL_VERSION = 1

        /** Arbitrary, and unlikely to collide with a host app's own codes. */
        const val REQUEST_CODE = 0x4543
    }
}

/**
 * The payment app was started and did not answer this request.
 *
 * Its own type because it means something no other channel failure does: the
 * transaction may have happened. It is mapped to a failure whose outcome is
 * unknown, which sends the till to inquire by its merchant reference rather
 * than retry.
 */
internal class PaymentAppInterrupted(message: String) : IOException(message)

/** What came back from the payment app, or why nothing did. */
internal sealed interface PaymentAppAnswer {
    class Body(val bytes: ByteArray) : PaymentAppAnswer
    class Interrupted(val reason: String) : PaymentAppAnswer
    class Broken(val reason: String) : PaymentAppAnswer
}

/**
 * Holds the one request that is with the payment app.
 *
 * One at a time, because the device has one screen and one cardholder. A
 * second is refused rather than queued: a till that is told "busy" retries,
 * while one left waiting behind a payment it cannot see has no way to reason
 * about what is happening.
 */
internal class PaymentAppResults : PluginRegistry.ActivityResultListener {

    private val busy = AtomicBoolean(false)
    private val handovers = ArrayBlockingQueue<PaymentAppAnswer>(1)

    /** Takes the slot, or null when it is already taken. */
    fun claim(): Waiting? {
        if (!busy.compareAndSet(false, true)) return null
        handovers.clear()
        return Waiting()
    }

    fun deliver(answer: PaymentAppAnswer) {
        // offer, not put: a late answer — one that arrives after the caller
        // gave up — finds the queue full or the slot released, and is dropped
        // rather than blocking the main thread.
        handovers.offer(answer)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PaymentAppEcrChannel.REQUEST_CODE) return false
        deliver(
            answerFor(
                resultCode = resultCode,
                body = data?.getStringExtra(PaymentAppEcrChannel.EXTRA_RESPONSE),
            ),
        )
        return true
    }

    /**
     * What a result from the payment app means.
     *
     * Apart from [Intent] so it can be tested: the difference between "this is
     * the answer", "the app went away" and "it answered with nothing" is the
     * whole of what a till has to act on, and it is not something to find out
     * on a terminal.
     */
    internal fun answerFor(resultCode: Int, body: String?): PaymentAppAnswer = when {
        !body.isNullOrEmpty() -> PaymentAppAnswer.Body(body.toByteArray(Charsets.UTF_8))

        // RESULT_CANCELED with nothing attached means the payment app was
        // destroyed before it could answer. It is never sent deliberately, and
        // it is the one result that says nothing at all about the money.
        resultCode == Activity.RESULT_CANCELED -> PaymentAppAnswer.Interrupted(
            "The payment app closed without answering. The transaction may have " +
                "completed — inquire by merchant reference before retrying.",
        )

        else -> PaymentAppAnswer.Interrupted(
            "The payment app answered with nothing. The transaction may have " +
                "completed — inquire by merchant reference before retrying.",
        )
    }

    inner class Waiting {
        fun await(timeout: Duration): PaymentAppAnswer? = try {
            handovers.poll(timeout.inWholeMilliseconds, TimeUnit.MILLISECONDS)
        } finally {
            busy.set(false)
        }
    }
}
