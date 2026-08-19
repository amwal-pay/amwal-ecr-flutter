package com.amwalpay.ecr.flutter

import java.math.BigDecimal
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.launch

/**
 * Where a channel call becomes an ECR operation.
 *
 * Holds two guarantees, and everything else here exists to serve them:
 *
 * 1. **One call, one reply.** Every path through this class ends in exactly one
 *    [EcrReply] call, and [OneShotReply] makes a second one a no-op rather than
 *    a crash — a reply after a cancel is late, not fatal.
 * 2. **Nothing is ever sent twice.** There is no retry here, at any level, for
 *    any failure. A duplicate money-moving request is a customer charged twice,
 *    and no timeout is worth that.
 *
 * Free of Flutter types on purpose: [EcrReply] is the only thing the plugin
 * adapts, so the whole of this logic is exercised by plain JVM unit tests.
 */
internal class EcrCallHandler(
    private val scope: CoroutineScope,
    private val terminals: EcrTerminalFactory,
) {

    /**
     * Operations the caller can still cancel, keyed by the Dart-generated
     * operation id.
     *
     * Concurrent because a cancel arrives on the platform thread while the
     * operation completes on another.
     */
    private val running = ConcurrentHashMap<String, Deferred<*>>()

    /** How many operations are in flight. For tests. */
    internal val inFlightCount: Int get() = running.size

    fun handle(method: String, arguments: Map<*, *>?, reply: EcrReply) {
        val once = OneShotReply(reply)
        try {
            when (method) {
                EcrMethods.CANCEL -> once.success(cancel(arguments.requireString(EcrArgs.OPERATION_ID)))
                EcrMethods.IS_REACHABLE -> reachable(Call(arguments), once)
                EcrMethods.SALE -> sale(Call(arguments), once)
                EcrMethods.VOID -> voidTransaction(Call(arguments), once)
                EcrMethods.REFUND -> refund(Call(arguments), once)
                EcrMethods.INQUIRE -> inquire(Call(arguments), once)
                EcrMethods.INQUIRE_BY_REFERENCE -> inquireByReference(Call(arguments), once)
                EcrMethods.RECEIPT -> receipt(Call(arguments), once)
                else -> once.notImplemented()
            }
        } catch (e: EcrInvalidArgument) {
            once.error(EcrErrorCodes.INVALID_ARGUMENT, e.message)
        } catch (e: IllegalArgumentException) {
            // The SDK's own `require`s land here. Same meaning: the request was
            // refused before anything was sent.
            once.error(EcrErrorCodes.INVALID_ARGUMENT, e.message)
        }
    }

    /**
     * Abandons the wait for [operationId].
     *
     * Answers whether anything was still running. **This does not stop the
     * terminal.** Nothing on the wire says "never mind": a cardholder halfway
     * through a PIN carries on, and the payment may well complete. What is
     * cancelled is this side's waiting, and the operation is reported as
     * cancelled — an unknown outcome, to be reconciled by an inquiry, never
     * retried.
     */
    private fun cancel(operationId: String): Boolean {
        val operation = running.remove(operationId) ?: return false
        operation.cancel(CancellationException("Cancelled by the caller"))
        return true
    }

    private fun reachable(call: Call, reply: EcrReply) {
        // A probe is not registered as cancellable: it is bounded by
        // probeTimeout, which is three seconds, and a cancel that arrives
        // inside that window has nothing useful to do.
        if (!call.isIpTransport) {
            reply.success(false)
            return
        }
        scope.launch {
            reply.settle { call.terminal(terminals).isReachable() }
        }
    }

    private fun sale(call: Call, reply: EcrReply) {
        val amount = call.requiredAmount()
        call.run(reply, EcrMapping::result) { it.sale(amount, call.merchantReferenceId) }
    }

    private fun voidTransaction(call: Call, reply: EcrReply) {
        val receiptNumber = call.requiredReceiptNumber("A void")
        call.run(reply, EcrMapping::result) {
            it.void(receiptNumber, call.originalTerminalId, call.merchantReferenceId)
        }
    }

    private fun refund(call: Call, reply: EcrReply) {
        val amount = call.requiredAmount()
        val receiptNumber = call.requiredReceiptNumber("A refund")
        call.run(reply, EcrMapping::result) {
            it.refund(
                amount,
                receiptNumber,
                call.transactionDate,
                call.originalTerminalId,
                call.merchantReferenceId,
            )
        }
    }

    private fun inquire(call: Call, reply: EcrReply) {
        val receiptNumber = call.requiredReceiptNumber("An inquiry")
        call.run(reply, EcrMapping::inquiry) {
            it.inquire(
                receiptNumber,
                call.transactionDate,
                call.originalTerminalId,
                call.merchantReferenceId,
            )
        }
    }

    private fun inquireByReference(call: Call, reply: EcrReply) {
        val originalReference = call.requiredOriginalReference()
        call.run(reply, EcrMapping::inquiry) {
            it.inquireByReference(
                originalReference,
                call.transactionDate,
                call.originalTerminalId,
                call.merchantReferenceId,
            )
        }
    }

    private fun receipt(call: Call, reply: EcrReply) {
        val receiptNumber = call.requiredReceiptNumber("A receipt")
        call.run(reply, EcrMapping::receipt) {
            it.receipt(
                receiptNumber,
                call.transactionDate,
                call.originalTerminalId,
                call.merchantReferenceId,
            )
        }
    }

    /**
     * Runs one operation, registers it so it can be cancelled, and replies
     * exactly once with [encode]'s map.
     */
    private fun <T> Call.run(
        reply: EcrReply,
        encode: (T) -> Map<String, Any?>,
        block: suspend (EcrTerminalPort) -> T,
    ) {
        if (!isIpTransport) {
            reply.success(
                EcrMapping.failedResult(
                    EcrFailureKinds.UNSUPPORTED,
                    "A terminal opens its ECR listener only for the IP transports " +
                        "(ethernet, wifi). \"$transport\" is driven by other machinery, " +
                        "so nothing was sent.",
                ),
            )
            return
        }

        val port = terminal(terminals)

        // async rather than launch: cancelling the deferred lets the awaiting
        // coroutine below answer immediately, without waiting for the blocking
        // socket read to unwind. The orphaned read finishes on its own and its
        // answer is discarded — which is exactly what "the outcome is unknown"
        // means.
        //
        // The failure is caught *inside* the async and carried out as a value.
        // An async that fails cancels its parent, and the parent here is the
        // caller's scope: one terminal throwing would take down every other
        // operation on it — including the inquiry that is the only way to find
        // out what happened to this one.
        val work: Deferred<Attempt<T>> = scope.async {
            try {
                Attempt.Done(block(port))
            } catch (e: CancellationException) {
                // Not a failure. Rethrown so the deferred is cancelled rather
                // than reporting a cancellation as something that broke.
                throw e
            } catch (t: Throwable) {
                Attempt.Broke(t)
            }
        }
        running[operationId] = work

        scope.launch {
            try {
                when (val attempt = work.await()) {
                    is Attempt.Done -> reply.success(encode(attempt.value))
                    is Attempt.Broke -> reply.error(
                        EcrErrorCodes.INTERNAL,
                        attempt.error.message ?: attempt.error::class.java.simpleName,
                    )
                }
            } catch (e: CancellationException) {
                reply.success(
                    EcrMapping.failedResult(
                        EcrFailureKinds.CANCELLED,
                        "The caller cancelled while the terminal had the request. " +
                            "The transaction may still have completed — inquire before retrying.",
                    ),
                )
            } catch (e: Throwable) {
                reply.error(EcrErrorCodes.INTERNAL, e.message ?: e::class.java.simpleName)
            } finally {
                // remove(key, value) so a second operation that reused the id
                // after this one finished is not deregistered by mistake.
                running.remove(operationId, work)
            }
        }
    }

    /** What an operation produced: its answer, or what broke instead. */
    private sealed interface Attempt<out T> {
        data class Done<T>(val value: T) : Attempt<T>
        data class Broke(val error: Throwable) : Attempt<Nothing>
    }

    /** Runs [block] and replies with its value, or with an internal error. */
    private suspend fun EcrReply.settle(block: suspend () -> Any?) {
        try {
            success(block())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            error(EcrErrorCodes.INTERNAL, e.message ?: e::class.java.simpleName)
        }
    }

    /** One call's arguments, read once and checked as they are read. */
    private class Call(arguments: Map<*, *>?) {
        private val map: Map<*, *> = arguments
            ?: throw EcrInvalidArgument("The call carried no arguments")

        val operationId: String = map.requireString(EcrArgs.OPERATION_ID)
        val host: String = map.requireString(EcrArgs.HOST)
        val serialNumber: String = map[EcrArgs.SERIAL_NUMBER] as? String ?: ""
        val transport: String = map[EcrArgs.TRANSPORT] as? String ?: EcrTransports.WIFI
        val transactionDate: String = map[EcrArgs.TRANSACTION_DATE] as? String ?: ""
        val originalTerminalId: String = map[EcrArgs.ORIGINAL_TERMINAL_ID] as? String ?: ""
        val merchantReferenceId: String = map[EcrArgs.MERCHANT_REFERENCE_ID] as? String ?: ""

        val isIpTransport: Boolean get() = EcrTransports.isIpTransport(transport)

        private val config = EcrMapping.config(map[EcrArgs.CONFIG] as? Map<*, *>)

        fun terminal(factory: EcrTerminalFactory): EcrTerminalPort =
            factory.create(host, serialNumber, config)

        fun requiredAmount(): BigDecimal = EcrMapping.amount(map[EcrArgs.AMOUNT])
            ?: throw EcrInvalidArgument("This operation needs an amount")

        fun requiredReceiptNumber(operation: String): String {
            val value = (map[EcrArgs.RECEIPT_NUMBER] as? String)?.trim().orEmpty()
            if (value.isEmpty()) {
                throw EcrInvalidArgument("$operation needs the original's receipt number")
            }
            return value
        }

        fun requiredOriginalReference(): String {
            val value = (map[EcrArgs.ORIGINAL_MERCHANT_REFERENCE] as? String)?.trim().orEmpty()
            if (value.isEmpty()) {
                throw EcrInvalidArgument(
                    "An inquiry by reference needs the original's reference",
                )
            }
            return value
        }
    }
}

private fun Map<*, *>?.requireString(key: String): String {
    val value = this?.get(key) as? String
    if (value.isNullOrEmpty()) {
        throw EcrInvalidArgument("\"$key\" is required and was $value")
    }
    return value
}

/**
 * Where a call's answer goes.
 *
 * `MethodChannel.Result` in production; a recorder in tests.
 */
internal interface EcrReply {
    fun success(value: Any?)
    fun error(code: String, message: String?)
    fun notImplemented()
}

/**
 * Lets the first answer through and drops the rest.
 *
 * The late-callback guard. Answering a Flutter method call twice throws inside
 * the engine and takes the app with it, and the one time it happens is the one
 * time it must not: a terminal replying after the operator has already
 * cancelled and moved on.
 */
internal class OneShotReply(private val delegate: EcrReply) : EcrReply {

    @Volatile
    private var answered = false

    /** Whether the answer has been delivered. For tests. */
    internal val hasAnswered: Boolean get() = answered

    @Synchronized
    private fun claim(): Boolean {
        if (answered) return false
        answered = true
        return true
    }

    override fun success(value: Any?) {
        if (claim()) delegate.success(value)
    }

    override fun error(code: String, message: String?) {
        if (claim()) delegate.error(code, message)
    }

    override fun notImplemented() {
        if (claim()) delegate.notImplemented()
    }
}
