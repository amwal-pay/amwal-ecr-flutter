import Foundation
import AmwalECR

/// Where a channel call becomes an ECR operation.
///
/// The mirror of `EcrCallHandler.kt`, holding the same two guarantees:
///
/// 1. **One call, one reply.** Every path ends in exactly one [EcrReply] call,
///    and [OneShotReply] makes a second one a no-op — a terminal answering
///    after the operator has cancelled is late, not fatal.
/// 2. **Nothing is ever sent twice.** No retry, at any level, for any failure.
///
/// Free of Flutter types on purpose: [EcrReply] is all the plugin adapts, so
/// this logic is exercised by plain unit tests.
final class EcrCallHandler {

    private let terminals: EcrTerminalFactory

    /// Blocking socket work. Concurrent because a till may hold a sale open at
    /// the terminal and still want an inquiry answered beside it — which is
    /// precisely the case the protocol keeps inquiries non-blocking for.
    private let queue = DispatchQueue(
        label: "com.amwalpay.ecr.operations",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private var running: [String: Operation] = [:]
    private let lock = NSLock()

    /// How many operations are in flight. For tests.
    var inFlightCount: Int {
        lock.lock(); defer { lock.unlock() }
        return running.count
    }

    init(terminals: @escaping EcrTerminalFactory = makeNativeTerminal) {
        self.terminals = terminals
    }

    /// One in-flight call: what to cancel, and who to answer.
    private final class Operation {
        let terminal: EcrTerminalPort
        let reply: OneShotReply

        init(terminal: EcrTerminalPort, reply: OneShotReply) {
            self.terminal = terminal
            self.reply = reply
        }
    }

    func handle(method: String, arguments: [String: Any]?, reply: EcrReply) {
        let once = OneShotReply(reply)

        do {
            switch method {
            case EcrMethods.cancel:
                once.success(cancel(try requireString(arguments, EcrArgs.operationId)))
            case EcrMethods.isReachable:
                try reachable(Call(arguments), once)
            case EcrMethods.sale:
                try sale(Call(arguments), once)
            case EcrMethods.void_:
                try voidTransaction(Call(arguments), once)
            case EcrMethods.refund:
                try refund(Call(arguments), once)
            case EcrMethods.inquire:
                try inquire(Call(arguments), once)
            case EcrMethods.inquireByReference:
                try inquireByReference(Call(arguments), once)
            case EcrMethods.receipt:
                try receipt(Call(arguments), once)
            default:
                once.notImplemented()
            }
        } catch let error as EcrInvalidArgument {
            once.error(code: EcrErrorCodes.invalidArgument, message: error.message)
        } catch {
            once.error(code: EcrErrorCodes.internalError, message: error.localizedDescription)
        }
    }

    /// Abandons the wait for [operationId].
    ///
    /// Answers whether anything was still running. **This does not stop the
    /// terminal.** Nothing on the wire says "never mind": a cardholder halfway
    /// through a PIN carries on, and the payment may well complete. What is
    /// cancelled is this side's waiting.
    ///
    /// The caller is answered here and now, with `cancelled`, rather than left
    /// waiting for the socket to unwind — the same instant answer the Android
    /// host gives. The terminal's real reply, when it comes, is dropped by
    /// [OneShotReply].
    private func cancel(_ operationId: String) -> Bool {
        lock.lock()
        let operation = running.removeValue(forKey: operationId)
        lock.unlock()

        guard let operation = operation else { return false }

        operation.terminal.cancel()
        operation.reply.success(
            EcrMapping.failedResult(
                kind: EcrFailureKinds.cancelled,
                message: "The caller cancelled while the terminal had the request. "
                    + "The transaction may still have completed — inquire before retrying."
            )
        )
        return true
    }

    private func reachable(_ call: Call, _ reply: EcrReply) throws {
        // Not registered as cancellable: a probe is bounded by probeTimeout,
        // which is three seconds, and a cancel inside that window has nothing
        // useful to do.
        guard call.isIpTransport else {
            reply.success(false)
            return
        }
        let terminal = call.terminal(terminals)
        queue.async { reply.success(terminal.isReachable()) }
    }

    private func sale(_ call: Call, _ reply: OneShotReply) throws {
        let amount = try call.requiredAmount()
        try run(call, reply, EcrMapping.result) {
            try $0.sale(amount: amount, merchantReferenceId: call.merchantReferenceId)
        }
    }

    private func voidTransaction(_ call: Call, _ reply: OneShotReply) throws {
        let receiptNumber = try call.requiredReceiptNumber("A void")
        try run(call, reply, EcrMapping.result) {
            try $0.void(
                receiptNumber: receiptNumber,
                originalTerminalId: call.originalTerminalId,
                merchantReferenceId: call.merchantReferenceId
            )
        }
    }

    private func refund(_ call: Call, _ reply: OneShotReply) throws {
        let amount = try call.requiredAmount()
        let receiptNumber = try call.requiredReceiptNumber("A refund")
        try run(call, reply, EcrMapping.result) {
            try $0.refund(
                amount: amount,
                receiptNumber: receiptNumber,
                transactionDate: call.transactionDate,
                originalTerminalId: call.originalTerminalId,
                merchantReferenceId: call.merchantReferenceId
            )
        }
    }

    private func inquire(_ call: Call, _ reply: OneShotReply) throws {
        let receiptNumber = try call.requiredReceiptNumber("An inquiry")
        try run(call, reply, EcrMapping.inquiry) {
            try $0.inquire(
                receiptNumber: receiptNumber,
                transactionDate: call.transactionDate,
                originalTerminalId: call.originalTerminalId,
                merchantReferenceId: call.merchantReferenceId
            )
        }
    }

    private func inquireByReference(_ call: Call, _ reply: OneShotReply) throws {
        let originalReference = try call.requiredOriginalReference()
        try run(call, reply, EcrMapping.inquiry) {
            try $0.inquireByReference(
                originalReference,
                transactionDate: call.transactionDate,
                originalTerminalId: call.originalTerminalId,
                merchantReferenceId: call.merchantReferenceId
            )
        }
    }

    private func receipt(_ call: Call, _ reply: OneShotReply) throws {
        let receiptNumber = try call.requiredReceiptNumber("A receipt")
        try run(call, reply, EcrMapping.receipt) {
            try $0.receipt(
                receiptNumber: receiptNumber,
                transactionDate: call.transactionDate,
                originalTerminalId: call.originalTerminalId,
                merchantReferenceId: call.merchantReferenceId
            )
        }
    }

    /// Runs one operation, registers it so it can be cancelled, and replies
    /// exactly once with [encode]'s map.
    private func run<T>(
        _ call: Call,
        _ reply: OneShotReply,
        _ encode: @escaping (T) -> [String: Any],
        _ block: @escaping (EcrTerminalPort) throws -> T
    ) throws {
        guard call.isIpTransport else {
            reply.success(
                EcrMapping.failedResult(
                    kind: EcrFailureKinds.unsupported,
                    message: "A terminal opens its ECR listener only for the IP transports "
                        + "(ethernet, wifi). \"\(call.transport)\" is driven by other machinery, "
                        + "so nothing was sent."
                )
            )
            return
        }

        let terminal = call.terminal(terminals)
        let operationId = call.operationId

        lock.lock()
        running[operationId] = Operation(terminal: terminal, reply: reply)
        lock.unlock()

        queue.async { [weak self] in
            defer { self?.deregister(operationId) }
            do {
                reply.success(encode(try block(terminal)))
            } catch let error as EcrInvalidArgument {
                reply.error(code: EcrErrorCodes.invalidArgument, message: error.message)
            } catch {
                reply.error(code: EcrErrorCodes.internalError, message: error.localizedDescription)
            }
        }
    }

    private func deregister(_ operationId: String) {
        lock.lock()
        running.removeValue(forKey: operationId)
        lock.unlock()
    }

    /// One call's arguments, read once and checked as they are read.
    private struct Call {
        let operationId: String
        let host: String
        let serialNumber: String
        let transport: String
        let transactionDate: String
        let originalTerminalId: String
        let merchantReferenceId: String

        private let raw: [String: Any]
        private let config: EcrConfig

        init(_ arguments: [String: Any]?) throws {
            guard let arguments = arguments else {
                throw EcrInvalidArgument("The call carried no arguments")
            }
            raw = arguments
            operationId = try requireString(arguments, EcrArgs.operationId)
            host = try requireString(arguments, EcrArgs.host)
            serialNumber = arguments[EcrArgs.serialNumber] as? String ?? ""
            transport = arguments[EcrArgs.transport] as? String ?? EcrTransports.wifi
            transactionDate = arguments[EcrArgs.transactionDate] as? String ?? ""
            originalTerminalId = arguments[EcrArgs.originalTerminalId] as? String ?? ""
            merchantReferenceId = arguments[EcrArgs.merchantReferenceId] as? String ?? ""
            config = EcrMapping.config(arguments[EcrArgs.config] as? [String: Any])
        }

        var isIpTransport: Bool { EcrTransports.isIpTransport(transport) }

        func terminal(_ factory: EcrTerminalFactory) -> EcrTerminalPort {
            factory(host, serialNumber, config)
        }

        func requiredAmount() throws -> Decimal {
            guard let amount = try EcrMapping.amount(raw[EcrArgs.amount]) else {
                throw EcrInvalidArgument("This operation needs an amount")
            }
            return amount
        }

        func requiredReceiptNumber(_ operation: String) throws -> String {
            let value = (raw[EcrArgs.receiptNumber] as? String)?.trimmed ?? ""
            guard !value.isEmpty else {
                throw EcrInvalidArgument("\(operation) needs the original's receipt number")
            }
            return value
        }

        func requiredOriginalReference() throws -> String {
            let value = (raw[EcrArgs.originalMerchantReference] as? String)?.trimmed ?? ""
            guard !value.isEmpty else {
                throw EcrInvalidArgument("An inquiry by reference needs the original's reference")
            }
            return value
        }
    }
}

private func requireString(_ arguments: [String: Any]?, _ key: String) throws -> String {
    guard let value = arguments?[key] as? String, !value.isEmpty else {
        throw EcrInvalidArgument("\"\(key)\" is required and was missing")
    }
    return value
}

/// Where a call's answer goes.
///
/// `FlutterResult` in production; a recorder in tests.
protocol EcrReply: AnyObject {
    func success(_ value: Any?)
    func error(code: String, message: String?)
    func notImplemented()
}

/// Lets the first answer through and drops the rest.
///
/// The late-callback guard. Answering a Flutter method call twice is undefined
/// on the engine side, and the one time it happens is the one time it must not:
/// a terminal replying after the operator has already cancelled and moved on.
final class OneShotReply: EcrReply {

    private let delegate: EcrReply
    private let lock = NSLock()
    private var answered = false

    init(_ delegate: EcrReply) { self.delegate = delegate }

    /// Whether the answer has been delivered. For tests.
    var hasAnswered: Bool {
        lock.lock(); defer { lock.unlock() }
        return answered
    }

    private func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if answered { return false }
        answered = true
        return true
    }

    func success(_ value: Any?) {
        if claim() { delegate.success(value) }
    }

    func error(code: String, message: String?) {
        if claim() { delegate.error(code: code, message: message) }
    }

    func notImplemented() {
        if claim() { delegate.notImplemented() }
    }
}
