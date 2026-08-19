package com.amwalpay.ecr.flutter

import android.content.pm.ApplicationInfo
import android.util.Log
import com.amwalpay.ecr.EcrLogger
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * The Android host for `package:amwal_ecr`.
 *
 * Thin by design: it adapts Flutter's types to [EcrCallHandler] and gets out of
 * the way. Everything that decides an outcome lives in the handler and in
 * [EcrMapping], both of which are plain JVM classes with unit tests, because a
 * bug in how a decline is reported is not something to find on a terminal.
 */
class AmwalEcrPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel

    /**
     * SupervisorJob so one failed operation cannot take down the others: a
     * till may have a sale in flight and an inquiry beside it, and the inquiry
     * is precisely what is needed when the sale goes wrong.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * Whether the *host app* is a debug build, read from its manifest at
     * attach time. The plugin's own BuildConfig says nothing useful here: a
     * library ships one flavour and it is the app being debugged.
     */
    private var hostAppIsDebuggable = false

    /**
     * On in a debug build, as the Android example is; off in release.
     *
     * The SDK's diagnostics carry request and response payloads, including the
     * masked card number. They are safe to keep — they are transaction records
     * — but they do not belong in a release log by accident, and they are
     * exactly what is needed when a terminal is not answering.
     *
     * A release build can still be made to talk for one session:
     * `adb shell setprop log.tag.AmwalEcr DEBUG`
     */
    private val logger = EcrLogger { message -> log(message) }

    private fun log(message: String) {
        if (hostAppIsDebuggable || Log.isLoggable(LOG_TAG, Log.DEBUG)) {
            Log.d(LOG_TAG, message)
        }
    }

    private val handler = EcrCallHandler(
        scope = scope,
        terminals = { host, serialNumber, config ->
            SdkEcrTerminal(host, serialNumber, config, logger)
        },
    )

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        hostAppIsDebuggable = (
            binding.applicationContext.applicationInfo.flags and
                ApplicationInfo.FLAG_DEBUGGABLE
            ) != 0

        channel = MethodChannel(binding.binaryMessenger, ECR_METHOD_CHANNEL)
        channel.setMethodCallHandler(this)
        log("Plugin attached (debuggable=$hostAppIsDebuggable)")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // Cancels every operation still waiting. Their Dart futures are going
        // away with the engine, so there is nobody left to answer — but the
        // terminal may still complete what it was given, which is why a till
        // reconciles on restart rather than assuming.
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>

        // Logged before anything is decided, so a call that is refused on its
        // arguments or its transport — and therefore never reaches the SDK's
        // own logging — is still visible. Without this, "nothing happens" and
        // "nothing was sent" look identical from a logcat.
        log(
            "-> ${call.method} " +
                "op=${arguments?.get(EcrArgs.OPERATION_ID)} " +
                "host=${arguments?.get(EcrArgs.HOST)}:" +
                "${(arguments?.get(EcrArgs.CONFIG) as? Map<*, *>)?.get(EcrConfigKeys.PORT)} " +
                "transport=${arguments?.get(EcrArgs.TRANSPORT)}",
        )

        handler.handle(call.method, arguments, LoggingReply(ResultReply(result), ::log))
    }

    /**
     * Adapts Flutter's result to [EcrReply].
     *
     * Every call arrives on the platform thread and [EcrCallHandler] answers on
     * `Dispatchers.Main.immediate`, which is that same thread — so no hop is
     * needed here, and adding one would only widen the window in which an
     * engine detach could land between the answer and its delivery.
     */
    private class ResultReply(private val result: MethodChannel.Result) : EcrReply {
        override fun success(value: Any?) = result.success(value)
        override fun error(code: String, message: String?) = result.error(code, message, null)
        override fun notImplemented() = result.notImplemented()
    }

    /** Notes what was answered on its way past. */
    private class LoggingReply(
        private val delegate: EcrReply,
        private val log: (String) -> Unit,
    ) : EcrReply {
        override fun success(value: Any?) {
            log("<- ${describe(value)}")
            delegate.success(value)
        }

        override fun error(code: String, message: String?) {
            log("<- error $code: $message")
            delegate.error(code, message)
        }

        override fun notImplemented() {
            log("<- notImplemented")
            delegate.notImplemented()
        }

        /**
         * The outcome and why, without reprinting the terminal's whole answer —
         * the SDK has already logged that.
         */
        private fun describe(value: Any?): String {
            val map = value as? Map<*, *> ?: return value.toString()
            val outcome = map[EcrResultKeys.OUTCOME]
            val failure = map[EcrResultKeys.FAILURE] as? Map<*, *>
            return when {
                failure != null ->
                    "$outcome ${failure[EcrFailureKeys.KIND]}: ${failure[EcrFailureKeys.MESSAGE]}"
                map.containsKey(EcrResultKeys.RESPONSE_CODE) ->
                    "$outcome code=${map[EcrResultKeys.RESPONSE_CODE]} ${map[EcrResultKeys.REASON] ?: ""}"
                else -> outcome.toString()
            }
        }
    }

    private companion object {
        const val LOG_TAG = "AmwalEcr"
    }
}
