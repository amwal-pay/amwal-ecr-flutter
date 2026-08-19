import Flutter
import Foundation

/// The iOS host for `package:amwal_ecr`.
///
/// Thin by design: it adapts Flutter's types to `EcrCallHandler` and gets out
/// of the way. Everything that decides an outcome lives in the handler, in
/// `EcrMapping` and in the AmwalECR SDK, none of which import Flutter — because
/// a bug in how a decline is reported is not something to find on a terminal.
/// This is the only file in the plugin that knows Flutter exists.
public class AmwalEcrPlugin: NSObject, FlutterPlugin {

    private let handler = EcrCallHandler()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: kEcrMethodChannel,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(AmwalEcrPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any]

        // Logged before anything is decided, so a call refused on its arguments
        // or its transport — and therefore never reaching the socket — is still
        // visible. Without it, "nothing happened" and "nothing was sent" look
        // identical in a console log.
        let port = (arguments?[EcrArgs.config] as? [String: Any])?[EcrConfigKeys.port] ?? "?"
        AmwalEcrPlugin.log(
            "-> \(call.method) "
                + "op=\(arguments?[EcrArgs.operationId] ?? "?") "
                + "host=\(arguments?[EcrArgs.host] ?? "?"):\(port) "
                + "transport=\(arguments?[EcrArgs.transport] ?? "?")"
        )

        handler.handle(
            method: call.method,
            arguments: arguments,
            reply: LoggingReply(FlutterReply(result))
        )
    }

    /// On in a debug build, off in release.
    ///
    /// The messages carry request and response detail, including the masked
    /// card number. Safe to keep — they are transaction records — but they do
    /// not belong in a release log by accident, and they are exactly what is
    /// needed when a terminal is not answering.
    static func log(_ message: String) {
        #if DEBUG
        NSLog("[AmwalEcr] %@", message)
        #endif
    }

    /// Notes what was answered on its way past.
    private final class LoggingReply: EcrReply {

        private let delegate: EcrReply

        init(_ delegate: EcrReply) { self.delegate = delegate }

        func success(_ value: Any?) {
            AmwalEcrPlugin.log("<- \(describe(value))")
            delegate.success(value)
        }

        func error(code: String, message: String?) {
            AmwalEcrPlugin.log("<- error \(code): \(message ?? "")")
            delegate.error(code: code, message: message)
        }

        func notImplemented() {
            AmwalEcrPlugin.log("<- notImplemented")
            delegate.notImplemented()
        }

        /// The outcome and why, without reprinting the terminal's whole answer.
        private func describe(_ value: Any?) -> String {
            guard let map = value as? [String: Any] else { return String(describing: value) }
            let outcome = map[EcrResultKeys.outcome] ?? "?"
            if let failure = map[EcrResultKeys.failure] as? [String: Any] {
                return "\(outcome) \(failure[EcrFailureKeys.kind] ?? "?"): "
                    + "\(failure[EcrFailureKeys.message] ?? "")"
            }
            if let code = map[EcrResultKeys.responseCode] {
                return "\(outcome) code=\(code) \(map[EcrResultKeys.reason] ?? "")"
            }
            return "\(outcome)"
        }
    }

    /// Adapts Flutter's result block to `EcrReply`.
    ///
    /// A `FlutterResult` must be called on the platform thread. The handler
    /// answers from its own queue, so the hop back is made here rather than
    /// left to each call site to remember.
    private final class FlutterReply: EcrReply {

        private let result: FlutterResult

        init(_ result: @escaping FlutterResult) { self.result = result }

        func success(_ value: Any?) {
            onPlatformThread { self.result(value) }
        }

        func error(code: String, message: String?) {
            onPlatformThread {
                self.result(FlutterError(code: code, message: message, details: nil))
            }
        }

        func notImplemented() {
            onPlatformThread { self.result(FlutterMethodNotImplemented) }
        }

        /// `async` even when already on the main thread would be safe, but
        /// `sync` there would deadlock — so check, and only hop when there is
        /// somewhere to hop from.
        private func onPlatformThread(_ block: @escaping () -> Void) {
            if Thread.isMainThread {
                block()
            } else {
                DispatchQueue.main.async(execute: block)
            }
        }
    }
}
