import Foundation
import AmwalECR

/// The part of an ECR implementation this wrapper uses.
///
/// The seam. It is satisfied by `AmwalECR.EcrTerminal`, the published iOS SDK,
/// which speaks the protocol in `ecr-sdk/docs/protocol.md` directly. Swapping
/// in a different implementation — a fake in a test, or a future SDK — means
/// conforming its terminal type to this protocol and changing
/// [EcrTerminalFactory]; the handler, the mapping, the channel contract and the
/// whole Dart API stay exactly as they are.
///
/// The signatures are deliberately the Kotlin SDK's, so a reader comparing the
/// two hosts is comparing like with like.
protocol EcrTerminalPort: AnyObject {

    func isReachable() -> Bool

    func sale(amount: Decimal, merchantReferenceId: String) throws -> EcrResult

    func void(
        receiptNumber: String,
        originalTerminalId: String,
        merchantReferenceId: String
    ) throws -> EcrResult

    func refund(
        amount: Decimal,
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String
    ) throws -> EcrResult

    func inquire(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String
    ) throws -> EcrInquiry

    /// Looks a transaction up by the reference it was sent with.
    ///
    /// The only lookup available after an answer goes missing: a receipt number
    /// arrives *in* the answer, and the reference does not.
    func inquireByReference(
        _ originalReference: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String
    ) throws -> EcrInquiry

    func receipt(
        receiptNumber: String,
        transactionDate: String,
        originalTerminalId: String,
        merchantReferenceId: String
    ) throws -> EcrReceipt

    /// Abandons whatever is in flight. Called from another thread.
    func cancel()
}

/// `EcrTerminal` already has this shape; the conformance is the whole of it.
extension EcrTerminal: EcrTerminalPort {}

/// Builds the port for one call's terminal. Replaced in tests.
typealias EcrTerminalFactory = (_ host: String, _ serialNumber: String, _ config: EcrConfig) -> EcrTerminalPort

/// The default: the published AmwalECR SDK.
func makeNativeTerminal(host: String, serialNumber: String, config: EcrConfig) -> EcrTerminalPort {
    EcrTerminal(host: host, serialNumber: serialNumber, config: config)
}
