package com.amwalpay.ecr.flutter

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import com.amwalpay.ecr.EcrChannel
import com.amwalpay.ecr.EcrChannelTimeout
import com.amwalpay.ecr.EcrFrames
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.time.Duration

/**
 * Reaches the terminal down a USB cable, with no IP anywhere.
 *
 * This till is the USB host and the terminal is the accessory. Android Open
 * Accessory is what makes that pair talk: ask the terminal what protocol it
 * speaks, say who is calling, then tell it to switch. It drops off the bus and
 * comes back under Google's ids with one bulk endpoint each way, and those two
 * endpoints are the whole link.
 *
 * Bytes only. Signing the request, checking the answer and deciding what a
 * response code means all stay in `EcrTerminal`, exactly as they are over
 * Wi-Fi — this class is never asked to decide anything, which is why adding it
 * could not weaken what was already there.
 */
class UsbAccessoryEcrChannel(
    private val context: Context,
    private val log: (String) -> Unit = {},
) : EcrChannel {

    override val endpoint: String get() = "USB cable"

    /** No address. Reported as the link's own name rather than a made-up host. */
    override val host: String get() = endpoint
    override val port: Int get() = 0

    private val manager: UsbManager?
        get() = context.getSystemService(Context.USB_SERVICE) as? UsbManager

    override fun probe(timeout: Duration): String? {
        // Checked first and named plainly, because the answer is different in
        // kind from the others: an emulator has no USB bus at all and will
        // never see a cable, so "nothing is plugged in" would send someone off
        // to check a cable that was never the problem.
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)) {
            return "This device cannot act as a USB host, so it cannot reach a " +
                "terminal over a cable. An emulator never can. Run the simulator " +
                "on a phone that supports USB OTG, or use Wi‑Fi ECR instead."
        }

        val manager = manager ?: return "This device has no USB support"
        return when {
            accessory(manager) != null -> null
            candidate(manager) != null -> null
            manager.deviceList.isEmpty() ->
                "Nothing is plugged in. Connect the terminal with a USB cable."
            else ->
                "A USB device is connected but it is not a terminal in accessory mode."
        }
    }

    override fun exchange(body: ByteArray, timeout: Duration): ByteArray {
        val manager = manager ?: throw IOException("This device has no USB support")

        val device = accessory(manager)
            ?: switchIntoAccessoryMode(manager)
            ?: throw IOException(
                "The terminal did not come back in accessory mode. Check the cable " +
                    "and that the POS app is on USB cable mode.",
            )

        if (!awaitPermission(manager, device)) {
            throw IOException(
                "The terminal switched to accessory mode but this app was not " +
                    "allowed to open it. Accept the USB permission, or reinstall " +
                    "so Android grants it from the manifest.",
            )
        }

        val connection = manager.openDevice(device)
            ?: throw IOException("Could not open the terminal on the cable")

        try {
            val iface = device.getInterface(0)
            if (!connection.claimInterface(iface, true)) {
                throw IOException("Another app is holding the cable")
            }

            var input: UsbEndpoint? = null
            var output: UsbEndpoint? = null
            for (index in 0 until iface.endpointCount) {
                val candidate = iface.getEndpoint(index)
                if (candidate.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
                if (candidate.direction == UsbConstants.USB_DIR_IN) {
                    input = candidate
                } else {
                    output = candidate
                }
            }
            if (input == null || output == null) {
                throw IOException("The cable has no bulk endpoints to talk over")
            }

            discardStaleAnswers(connection, input)

            val expectedNonce = nonceOf(body)
            val millis = timeout.inWholeMilliseconds.toInt()
            val packet = EcrFrames.wrap(body)
            val written = connection.bulkTransfer(output, packet, packet.size, WRITE_TIMEOUT_MS)
            if (written < packet.size) {
                throw IOException("Only $written of ${packet.size} bytes reached the terminal")
            }

            return readFrame(connection, input, millis, expectedNonce)
        } finally {
            connection.close()
        }
    }

    /**
     * Throws away anything already waiting on the cable before a request goes
     * out.
     *
     * A socket gives each exchange a connection of its own, and an answer
     * nobody read dies with it. The cable does not: it is one pipe held open
     * for the life of the link, so an answer that arrived after its request had
     * given up stays there, and the *next* exchange reads it as its own.
     *
     * Measured against terminal 33527: a sale timed out, its answer was written
     * afterwards, and the following inquiry read that answer instead of its
     * own. The SDK caught it — the nonce did not match, and it reported the
     * outcome as unknown rather than believing the wrong record — but every
     * transaction after a single timeout then failed the same way, one stale
     * answer behind for good.
     *
     * Draining first costs one non-blocking read when the pipe is empty, which
     * is every ordinary exchange. It is not enough alone: a late answer can
     * still arrive *after* this drain and before the matching reply. [readFrame]
     * therefore also skips framed answers whose nonce does not match the
     * request that was just sent.
     */
    private fun discardStaleAnswers(connection: UsbDeviceConnection, input: UsbEndpoint) {
        val scratch = ByteArray(READ_SIZE)
        var dropped = 0
        while (true) {
            val read = connection.bulkTransfer(input, scratch, scratch.size, DRAIN_TIMEOUT_MS)
            if (read <= 0) break
            dropped += read
            if (dropped > MAX_DRAIN_BYTES) {
                // Something is producing faster than this can throw away, which
                // is not a backlog. Stop rather than loop for ever; the nonce
                // check downstream still refuses whatever comes back.
                log("Gave up draining the cable after $dropped bytes")
                break
            }
        }
        if (dropped > 0) log("Discarded $dropped stale bytes left on the cable")
    }

    /**
     * Reads one framed answer that belongs to [expectedNonce] when the request
     * was signed.
     *
     * A transfer is not a frame: one may carry several, or half of one. What
     * arrives is accumulated and the frame is cut out of it, because treating a
     * transfer as a message works on a short answer and fails on a real one.
     *
     * When [expectedNonce] is non-empty, frames that echo a different nonce —
     * late answers that arrived after the pre-send drain — are discarded and
     * reading continues until a match or the timeout.
     */
    private fun readFrame(
        connection: UsbDeviceConnection,
        input: UsbEndpoint,
        timeoutMillis: Int,
        expectedNonce: String,
    ): ByteArray {
        val buffer = ByteArray(READ_SIZE)
        var pending = ByteArray(0)
        val deadline = System.currentTimeMillis() + timeoutMillis

        while (true) {
            val remaining = (deadline - System.currentTimeMillis()).toInt()
            if (remaining <= 0) {
                throw EcrChannelTimeout("the terminal did not answer in time")
            }

            val read = connection.bulkTransfer(input, buffer, buffer.size, remaining)
            if (read < 0) {
                // A bulk read returns -1 on timeout as well as on error, and the
                // two are not the same thing: a timeout may mean the payment ran
                // and the answer was lost, so it must not read as a failure.
                if (System.currentTimeMillis() >= deadline) {
                    throw EcrChannelTimeout("the terminal did not answer in time")
                }
                continue
            }
            if (read == 0) continue

            pending += buffer.copyOf(read)

            while (true) {
                if (pending.size < EcrFrames.HEADER_BYTES) break

                val length = EcrFrames.bodyLength(pending)
                if (length <= 0) throw IOException("Terminal returned an empty message")
                if (pending.size < EcrFrames.HEADER_BYTES + length) break

                val body = pending.copyOfRange(
                    EcrFrames.HEADER_BYTES,
                    EcrFrames.HEADER_BYTES + length,
                )
                pending = pending.copyOfRange(
                    EcrFrames.HEADER_BYTES + length,
                    pending.size,
                )

                if (expectedNonce.isEmpty()) return body

                val answered = nonceOf(body)
                if (answered.isEmpty() || answered == expectedNonce) return body

                log(
                    "Discarded stale USB answer " +
                        "(nonce=$answered, expected=$expectedNonce)",
                )
            }
        }
    }

    /** Pulls the ECR `nonce` field from a JSON body, or empty when unsigned. */
    private fun nonceOf(body: ByteArray): String {
        if (body.isEmpty()) return ""
        return try {
            org.json.JSONObject(String(body, Charsets.UTF_8)).optString("nonce", "")
        } catch (_: Exception) {
            ""
        }
    }

    /** A device already in accessory mode, which is the case after the first send. */
    private fun accessory(manager: UsbManager): UsbDevice? =
        manager.deviceList.values.firstOrNull {
            it.vendorId == AOA_VENDOR && it.productId in AOA_PRODUCTS
        }

    /** Something plugged in that might be a terminal. */
    private fun candidate(manager: UsbManager): UsbDevice? =
        manager.deviceList.values.firstOrNull {
            !(it.vendorId == AOA_VENDOR && it.productId in AOA_PRODUCTS)
        }

    private fun switchIntoAccessoryMode(manager: UsbManager): UsbDevice? {
        val device = candidate(manager) ?: return null

        // The one dialog an operator should ever see: this is the terminal in
        // its ordinary mode, which no filter can declare because its ids are
        // the vendor's. Once it has switched, the accessory ids are declared
        // and Android grants the rest.
        if (!awaitPermission(manager, device)) {
            log("Permission to open ${device.deviceName} was not granted")
            return null
        }

        val connection = manager.openDevice(device) ?: return null
        try {
            val version = ByteArray(2)
            val read = connection.controlTransfer(
                0xC0, GET_PROTOCOL, 0, 0, version, version.size, CONTROL_TIMEOUT_MS,
            )
            if (read < 2) {
                log("The device at ${device.deviceName} does not speak accessory mode")
                return null
            }
            val protocol = (version[0].toInt() and 0xFF) or ((version[1].toInt() and 0xFF) shl 8)
            log("Accessory protocol version $protocol")
            if (protocol < 1) return null

            IDENTITY.forEachIndexed { index, value ->
                // NUL-terminated: the accessory protocol reads these as C strings,
                // and one sent without the terminator runs into whatever follows it.
                val bytes = (value + Char(0)).toByteArray(Charsets.UTF_8)
                connection.controlTransfer(
                    0x40, SEND_STRING, 0, index, bytes, bytes.size, CONTROL_TIMEOUT_MS,
                )
            }

            connection.controlTransfer(0x40, START, 0, 0, null, 0, CONTROL_TIMEOUT_MS)
            log("Asked the terminal to switch to accessory mode")
        } finally {
            connection.close()
        }

        // It leaves the bus and comes back under Google's ids.
        repeat(RECONNECT_ATTEMPTS) {
            Thread.sleep(RECONNECT_INTERVAL_MS)
            accessory(manager)?.let { return it }
        }
        return null
    }

    /**
     * Blocks until the operator answers the permission dialog.
     *
     * Called from the SDK's IO thread, never the main one, so waiting here does
     * not freeze the screen the dialog is drawn on.
     *
     * Usually returns at once. A device this app declares in
     * `res/xml/usb_device_filter.xml` is granted by Android on attach, and a
     * terminal in accessory mode is one of those - so the dialog is for the
     * first stage only, before the terminal has switched.
     *
     * @return whether this app may open [device].
     */
    private fun awaitPermission(manager: UsbManager, device: UsbDevice): Boolean {
        if (manager.hasPermission(device)) return true

        val latch = CountDownLatch(1)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action != ACTION_PERMISSION) return
                context.unregisterReceiver(this)
                latch.countDown()
            }
        }

        val filter = IntentFilter(ACTION_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
        manager.requestPermission(
            device,
            PendingIntent.getBroadcast(
                context, 0, Intent(ACTION_PERMISSION).setPackage(context.packageName), flags,
            ),
        )

        if (!latch.await(PERMISSION_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            runCatching { context.unregisterReceiver(receiver) }
            Log.w(TAG, "No answer to the USB permission dialog")
            return false
        }

        // The dialog was answered; whether it was answered "yes" is a separate
        // question, and only the manager knows.
        return manager.hasPermission(device)
    }

    private companion object {
        const val TAG = "UsbAccessoryEcrChannel"
        const val ACTION_PERMISSION = "com.amwalpay.ecr.flutter.USB_PERMISSION"

        /** What a device calls itself once it is in accessory mode. */
        const val AOA_VENDOR = 0x18D1
        val AOA_PRODUCTS = setOf(0x2D00, 0x2D01, 0x2D04, 0x2D05)

        const val GET_PROTOCOL = 51
        const val SEND_STRING = 52
        const val START = 53

        /**
         * Must match `res/xml/usb_accessory_filter.xml` in the POS app, or
         * Android hands the cable to nobody and the terminal never sees it.
         */
        val IDENTITY = listOf(
            "AmwalPay",                     // manufacturer
            "EcrBridge",                    // model
            "ECR requests over the cable",  // description
            "1.0",                          // version
            "https://amwal-pay.com",        // uri
            "0000000000000001",             // serial
        )

        const val CONTROL_TIMEOUT_MS = 2_000
        const val WRITE_TIMEOUT_MS = 3_000
        const val RECONNECT_ATTEMPTS = 20
        const val RECONNECT_INTERVAL_MS = 500L
        const val PERMISSION_TIMEOUT_SECONDS = 30L

        /** Big enough to take a whole USB transfer in one read. */
        const val READ_SIZE = 16 * 1024

        /**
         * Long enough that a frame already in the pipe is seen, short enough
         * that an empty pipe - every ordinary exchange - costs nothing.
         */
        const val DRAIN_TIMEOUT_MS = 50

        /** A backlog larger than this is not a backlog. */
        const val MAX_DRAIN_BYTES = 256 * 1024
    }
}
