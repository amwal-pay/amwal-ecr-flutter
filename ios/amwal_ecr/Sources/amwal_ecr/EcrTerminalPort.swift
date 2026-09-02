import Foundation
import AmwalECR

/// The part of an ECR implementation this wrapper uses.
///
/// The seam. Satisfied by [SdkLanTerminal], [SdkWebServiceTerminal], and test
/// doubles. Swapping in a different implementation means conforming a type to
/// this protocol and changing [EcrTerminalFactory]; the handler, the mapping,
/// the channel contract and the whole Dart API stay exactly as they are.
protocol EcrTerminalPort: AnyObject {

    func isReachable() -> Bool

    func sale(amount: Decimal, merchantReference: String) throws -> EcrResult

    func void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrResult

    func refund(
        amount: Decimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrResult

    func inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrInquiry

    func inquireByReference(
        _ originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrInquiry

    func receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReference: String
    ) throws -> EcrReceipt

    func cancel()
}

/// Builds the port for one call's terminal. Replaced in tests.
typealias EcrTerminalFactory = (
    _ host: String,
    _ serialNumber: String,
    _ transport: String,
    _ config: EcrConfig
) -> EcrTerminalPort

func makeNativeTerminal(
    host: String,
    serialNumber: String,
    transport: String,
    config: EcrConfig
) -> EcrTerminalPort {
    EcrSessionPorts.create(
        host: host,
        serialNumber: serialNumber,
        transport: transport,
        config: config
    )
}
