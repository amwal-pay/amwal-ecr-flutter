import Foundation
import AmwalECR

/// Builds [EcrTerminalPort] instances through [EcrSessions.plan] / [EcrSessions.open],
/// matching the Android simulator app's session-planning pattern.
enum EcrSessionPorts {

    static func create(
        host: String,
        serialNumber: String,
        transport: String,
        config: EcrConfig,
        logger: EcrLogger = .none
    ) -> EcrTerminalPort {
        guard let link = linkFor(host: host, transport: transport, config: config) else {
            return UnsupportedEcrTerminalPort(transport: transport)
        }
        let plan = EcrSessions.plan(
            link: link,
            config: config,
            rawSecureHashKey: config.secureHashKey
        )
        if !plan.isReady {
            return InvalidPlanTerminalPort(issues: plan.issues)
        }
        let session = EcrSessions.open(
            terminalSerial: serialNumber,
            plan: plan,
            logger: logger
        )
        return SdkOpenedSessionPort(session: session)
    }

    private static func linkFor(host: String, transport: String, config: EcrConfig) -> EcrLink? {
        if EcrTransports.isWebService(transport) {
            return .webService(merchantId: config.merchantId, terminalId: config.terminalId)
        }
        if transport == EcrTransports.wifi {
            return .lan(host: host, port: config.port)
        }
        // USB cable is Android-only (AOA). Reach UnsupportedEcrTerminalPort
        // with a typed failure rather than pretending it is LAN.
        if EcrTransports.isUsbCable(transport) {
            return nil
        }
        return nil
    }
}

final class SdkOpenedSessionPort: EcrTerminalPort {
    private let session: EcrOpenedSession

    init(session: EcrOpenedSession) {
        self.session = session
    }

    func isReachable() -> Bool {
        session.probeReachability()?.reachable == true
    }

    func probeReachability() -> EcrReachability {
        session.probeReachability()
            ?? EcrReachability(reachable: false, host: "", port: 0, endpoint: "webService")
    }

    func sale(amount: Decimal, merchantReference: String) throws -> EcrResult {
        try session.sale(amount: amount, merchantReference: merchantReference)
    }

    func void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrResult {
        try session.void(
            receiptNumber: receiptNumber,
            originalTerminalId: originalTerminalId,
            merchantReference: merchantReference
        )
    }

    func refund(
        amount: Decimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrResult {
        try session.refund(
            amount: amount,
            receiptNumber: receiptNumber,
            transactionDate: transactionDate,
            originalTerminalId: originalTerminalId,
            merchantReference: merchantReference
        )
    }

    func inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrInquiry {
        try session.inquire(
            receiptNumber: receiptNumber,
            transactionDate: transactionDate,
            originalTerminalId: originalTerminalId,
            merchantReference: merchantReference
        )
    }

    func inquireByReference(
        _ originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrInquiry {
        try session.inquireByReference(
            originalReference,
            transactionDate: transactionDate,
            originalTerminalId: originalTerminalId,
            merchantReference: merchantReference
        )
    }

    func receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrReceipt {
        try session.receipt(
            receiptNumber: receiptNumber,
            transactionDate: transactionDate,
            originalTerminalId: originalTerminalId,
            merchantReference: merchantReference
        )
    }

    func cancel() { session.cancel() }
}

final class UnsupportedEcrTerminalPort: EcrTerminalPort {
    private let message: String
    private let transport: String

    init(transport: String) {
        self.transport = transport
        message = unsupportedTransportMessage(transport)
    }

    func isReachable() -> Bool { false }

    func probeReachability() -> EcrReachability {
        EcrReachability(reachable: false, host: "", port: 0, endpoint: transport)
    }

    func sale(amount: Decimal, merchantReference: String) throws -> EcrResult { try unsupported() }

    func void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrResult { try unsupported() }

    func refund(
        amount: Decimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrResult { try unsupported() }

    func inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrInquiry { try unsupportedInquiry() }

    func inquireByReference(
        _ originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrInquiry { try unsupportedInquiry() }

    func receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrReceipt {
        throw EcrInvalidArgument(message)
    }

    func cancel() {}

    private func unsupported() throws -> EcrResult {
        throw EcrInvalidArgument(message)
    }

    private func unsupportedInquiry() throws -> EcrInquiry {
        throw EcrInvalidArgument(message)
    }
}

final class InvalidPlanTerminalPort: EcrTerminalPort {
    private let message: String

    init(issues: [String]) {
        message = issues.joined(separator: "; ").isEmpty
            ? "Terminal configuration is incomplete"
            : issues.joined(separator: "; ")
    }

    func isReachable() -> Bool { false }

    func probeReachability() -> EcrReachability {
        EcrReachability(reachable: false, host: "", port: 0, error: message, endpoint: "")
    }

    func sale(amount: Decimal, merchantReference: String) throws -> EcrResult {
        configFailed(merchantReference)
    }

    func void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrResult {
        configFailed(merchantReference)
    }

    func refund(
        amount: Decimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrResult {
        configFailed(merchantReference)
    }

    func inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrInquiry {
        configInquiryFailed(merchantReference)
    }

    func inquireByReference(
        _ originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrInquiry {
        configInquiryFailed(merchantReference)
    }

    func receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrReceipt {
        .failed(merchantReference: merchantReference, failure: .malformed(message))
    }

    func cancel() {}

    private func configFailed(_ merchantReference: String) -> EcrResult {
        .failed(merchantReference: merchantReference, failure: .malformed(message), recovered: nil)
    }

    private func configInquiryFailed(_ merchantReference: String) -> EcrInquiry {
        .failed(merchantReference: merchantReference, failure: .malformed(message))
    }
}

func unsupportedTransportMessage(_ transport: String) -> String {
    "A terminal opens its ECR listener for Wi‑Fi, USB cable (Android), or "
        + "Web Service REST. \"\(transport)\" is driven by other machinery, "
        + "so nothing was sent."
}
