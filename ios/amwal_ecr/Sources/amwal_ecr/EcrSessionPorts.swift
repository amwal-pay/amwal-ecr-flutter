import Foundation
import AmwalECR

/// Builds [EcrTerminalPort] instances through [EcrSessions.plan], matching the
/// Android simulator app's session-planning pattern.
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
        if plan.usesWebService {
            return SdkWebServiceTerminal(serialNumber: serialNumber, plan: plan, logger: logger)
        }
        if plan.usesLan {
            return SdkLanTerminal(serialNumber: serialNumber, plan: plan, logger: logger)
        }
        return UnsupportedEcrTerminalPort(transport: transport)
    }

    private static func linkFor(host: String, transport: String, config: EcrConfig) -> EcrLink? {
        switch transport {
        case EcrTransports.webService:
            return .webService(merchantId: config.merchantId, terminalId: config.terminalId)
        case EcrTransports.ethernet, EcrTransports.wifi:
            return .lan(host: host, port: config.port)
        default:
            return nil
        }
    }
}

final class SdkLanTerminal: EcrTerminalPort {
    private let terminal: EcrTerminal

    init(serialNumber: String, plan: EcrSessionPlan, logger: EcrLogger) {
        terminal = EcrSessions.lanTerminal(
            terminalSerial: serialNumber,
            plan: plan,
            logger: logger
        )
    }

    func isReachable() -> Bool { terminal.probeReachability().reachable }

    func sale(amount: Decimal, merchantReference: String) throws -> EcrResult {
        try terminal.sale(amount: amount, merchantReference: merchantReference)
    }

    func void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrResult {
        try terminal.void(
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
        try terminal.refund(
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
        try terminal.inquire(
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
        try terminal.inquireByReference(
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
        try terminal.receipt(
            receiptNumber: receiptNumber,
            transactionDate: transactionDate,
            originalTerminalId: originalTerminalId,
            merchantReference: merchantReference
        )
    }

    func cancel() { terminal.cancel() }
}

final class SdkWebServiceTerminal: EcrTerminalPort {
    private let terminal: EcrWebServiceTerminal

    init(serialNumber: String, plan: EcrSessionPlan, logger: EcrLogger) {
        terminal = EcrSessions.webServiceTerminal(
            terminalSerial: serialNumber,
            plan: plan,
            logger: logger
        )
    }

    func isReachable() -> Bool { false }

    func sale(amount: Decimal, merchantReference: String) throws -> EcrResult {
        try terminal.sale(amount: amount, merchantReference: merchantReference)
    }

    func void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrResult {
        try terminal.void(receiptNumber: receiptNumber, merchantReference: merchantReference)
    }

    func refund(
        amount: Decimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrResult {
        try terminal.refund(
            amount: amount,
            receiptNumber: receiptNumber,
            transactionDate: transactionDate,
            merchantReference: merchantReference
        )
    }

    func inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrInquiry {
        try terminal.inquire(
            receiptNumber: receiptNumber,
            transactionDate: transactionDate,
            merchantReference: merchantReference
        )
    }

    func inquireByReference(
        _ originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrInquiry {
        try terminal.inquireByReference(
            originalReference: originalReference,
            transactionDate: transactionDate,
            merchantReference: merchantReference
        )
    }

    func receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrReceipt {
        throw EcrInvalidArgument("Receipt is LAN-only")
    }

    func cancel() {}
}

final class UnsupportedEcrTerminalPort: EcrTerminalPort {
    private let message: String

    init(transport: String) {
        message = unsupportedTransportMessage(transport)
    }

    func isReachable() -> Bool { false }

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
    "A terminal opens its ECR listener only for the IP transports "
        + "(ethernet, wifi) or Web Service REST. \"\(transport)\" is driven by "
        + "other machinery, so nothing was sent."
}
