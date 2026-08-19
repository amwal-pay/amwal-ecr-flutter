import XCTest
import AmwalECR
@testable import AmwalEcrBridge

/// The contract, frozen — the iOS copy.
///
/// The same literals are asserted in `test/platform/channel_contract_test.dart`
/// and `EcrChannelContractTest.kt`. Nothing in the toolchain checks that the
/// three agree, so each writes the strings out again by hand.
///
/// **Changing a value in this file is not how you rename something.** Rename it
/// in all three contracts and all three tests, in one commit, and treat it as a
/// breaking change.
final class EcrChannelContractTests: XCTestCase {

    func testMethodNamesAreSpelledExactlyThisWay() {
        XCTAssertEqual("isReachable", EcrMethods.isReachable)
        XCTAssertEqual("sale", EcrMethods.sale)
        XCTAssertEqual("void", EcrMethods.void_)
        XCTAssertEqual("refund", EcrMethods.refund)
        XCTAssertEqual("inquire", EcrMethods.inquire)
        XCTAssertEqual("inquireByReference", EcrMethods.inquireByReference)
        XCTAssertEqual("receipt", EcrMethods.receipt)
        XCTAssertEqual("cancel", EcrMethods.cancel)
    }

    func testArgumentKeysAreSpelledExactlyThisWay() {
        XCTAssertEqual("operationId", EcrArgs.operationId)
        XCTAssertEqual("host", EcrArgs.host)
        XCTAssertEqual("serialNumber", EcrArgs.serialNumber)
        XCTAssertEqual("transport", EcrArgs.transport)
        XCTAssertEqual("config", EcrArgs.config)
        XCTAssertEqual("amount", EcrArgs.amount)
        XCTAssertEqual("receiptNumber", EcrArgs.receiptNumber)
        XCTAssertEqual("transactionDate", EcrArgs.transactionDate)
        XCTAssertEqual("originalTerminalId", EcrArgs.originalTerminalId)
        XCTAssertEqual("merchantReferenceId", EcrArgs.merchantReferenceId)
        XCTAssertEqual("originalMerchantReference", EcrArgs.originalMerchantReference)
    }

    func testConfigKeysNameTheirUnit() {
        XCTAssertEqual("ecrId", EcrConfigKeys.ecrId)
        XCTAssertEqual("currencyCode", EcrConfigKeys.currencyCode)
        XCTAssertEqual("minorUnitDigits", EcrConfigKeys.minorUnitDigits)
        XCTAssertEqual("port", EcrConfigKeys.port)
        // The Ms suffix is load-bearing: Duration and TimeInterval disagree
        // about units, and a key that does not name one invites a guess.
        XCTAssertEqual("connectTimeoutMs", EcrConfigKeys.connectTimeoutMs)
        XCTAssertEqual("responseTimeoutMs", EcrConfigKeys.responseTimeoutMs)
        XCTAssertEqual("probeTimeoutMs", EcrConfigKeys.probeTimeoutMs)
        XCTAssertEqual("secureHashKey", EcrConfigKeys.secureHashKey)
        XCTAssertEqual("autoInquireOnFailure", EcrConfigKeys.autoInquireOnFailure)
    }

    func testResultKeysAreSpelledExactlyThisWay() {
        XCTAssertEqual("outcome", EcrResultKeys.outcome)
        XCTAssertEqual("merchantReferenceId", EcrResultKeys.merchantReferenceId)
        XCTAssertEqual("amount", EcrResultKeys.amount)
        XCTAssertEqual("responseCode", EcrResultKeys.responseCode)
        // The wire calls it responseMessage; the channel calls it reason.
        XCTAssertEqual("reason", EcrResultKeys.reason)
        XCTAssertEqual("rrn", EcrResultKeys.rrn)
        XCTAssertEqual("authCode", EcrResultKeys.authCode)
        XCTAssertEqual("maskedPan", EcrResultKeys.maskedPan)
        XCTAssertEqual("partialApproval", EcrResultKeys.partialApproval)
        XCTAssertEqual("requestedAmount", EcrResultKeys.requestedAmount)
        XCTAssertEqual("raw", EcrResultKeys.raw)
        XCTAssertEqual("failure", EcrResultKeys.failure)
        XCTAssertEqual("transaction", EcrResultKeys.transaction)
        XCTAssertEqual("url", EcrResultKeys.url)
        XCTAssertEqual("nextStep", EcrResultKeys.nextStep)
        XCTAssertEqual("recovered", EcrResultKeys.recovered)
    }

    func testOutcomesAreSpelledExactlyThisWay() {
        XCTAssertEqual("approved", EcrOutcomes.approved)
        XCTAssertEqual("declined", EcrOutcomes.declined)
        XCTAssertEqual("failed", EcrOutcomes.failed)
        XCTAssertEqual("found", EcrOutcomes.found)
        XCTAssertEqual("notFound", EcrOutcomes.notFound)
        XCTAssertEqual("ready", EcrOutcomes.ready)
        XCTAssertEqual("unavailable", EcrOutcomes.unavailable)
    }

    func testFailureKindsAreSpelledExactlyThisWay() {
        XCTAssertEqual("unreachable", EcrFailureKinds.unreachable)
        XCTAssertEqual("timeout", EcrFailureKinds.timeout)
        XCTAssertEqual("malformed", EcrFailureKinds.malformed)
        XCTAssertEqual("connectionLost", EcrFailureKinds.connectionLost)
        XCTAssertEqual("unauthenticated", EcrFailureKinds.unauthenticated)
        XCTAssertEqual("cancelled", EcrFailureKinds.cancelled)
        XCTAssertEqual("unsupported", EcrFailureKinds.unsupported)
        XCTAssertEqual("NONE", EcrNextSteps.none)
        XCTAssertEqual(
            "INQUIRE_BY_MERCHANT_REFERENCE",
            EcrNextSteps.inquireByMerchantReference
        )
        XCTAssertEqual("kind", EcrFailureKeys.kind)
        XCTAssertEqual("message", EcrFailureKeys.message)
    }

    func testTransactionKeysAreSpelledExactlyThisWay() {
        XCTAssertEqual("transactionId", EcrTransactionKeys.transactionId)
        XCTAssertEqual("stan", EcrTransactionKeys.stan)
        XCTAssertEqual("type", EcrTransactionKeys.type)
        XCTAssertEqual("status", EcrTransactionKeys.status)
        XCTAssertEqual("amount", EcrTransactionKeys.amount)
        XCTAssertEqual("totalAmount", EcrTransactionKeys.totalAmount)
        XCTAssertEqual("currency", EcrTransactionKeys.currency)
        XCTAssertEqual("transactionTime", EcrTransactionKeys.transactionTime)
        XCTAssertEqual("maskedPan", EcrTransactionKeys.maskedPan)
        XCTAssertEqual("cardHolderName", EcrTransactionKeys.cardHolderName)
        XCTAssertEqual("rrn", EcrTransactionKeys.rrn)
        XCTAssertEqual("authCode", EcrTransactionKeys.authCode)
        XCTAssertEqual("batchId", EcrTransactionKeys.batchId)
        XCTAssertEqual("terminalId", EcrTransactionKeys.terminalId)
        XCTAssertEqual("isRefunded", EcrTransactionKeys.isRefunded)
        XCTAssertEqual("canVoid", EcrTransactionKeys.canVoid)
        XCTAssertEqual("canRefund", EcrTransactionKeys.canRefund)
    }

    func testErrorCodesAndChannelName() {
        XCTAssertEqual("ecr_invalid_argument", EcrErrorCodes.invalidArgument)
        XCTAssertEqual("ecr_internal", EcrErrorCodes.internalError)
        XCTAssertEqual("com.amwalpay.ecr/methods", kEcrMethodChannel)
    }

    func testOnlyTheIpTransportsHaveAListenerToReach() {
        XCTAssertTrue(EcrTransports.isIpTransport("ethernet"))
        XCTAssertTrue(EcrTransports.isIpTransport("wifi"))
        XCTAssertFalse(EcrTransports.isIpTransport("bluetooth"))
        XCTAssertFalse(EcrTransports.isIpTransport("webService"))
        // A transport this build has not heard of is not an IP one either:
        // guessing would open a socket nothing is listening on.
        XCTAssertFalse(EcrTransports.isIpTransport("carrier-pigeon"))
        XCTAssertFalse(EcrTransports.isIpTransport(nil))
    }

    func testMessageTypesMatchTheProtocolDocument() {
        XCTAssertEqual("SALE", EcrTransactionType.sale.rawValue)
        XCTAssertEqual("VOID", EcrTransactionType.void.rawValue)
        XCTAssertEqual("REFUND", EcrTransactionType.refund.rawValue)
        XCTAssertEqual("INQUIRY", EcrTransactionType.inquiry.rawValue)
        XCTAssertEqual("RECEIPT", EcrTransactionType.receipt.rawValue)
    }

    func testEachTypeDeclaresWhatTheCallerMustSupply() {
        XCTAssertTrue(EcrTransactionType.sale.requiresAmount)
        XCTAssertFalse(EcrTransactionType.sale.requiresOriginalStan)

        // A void takes the original's amount; only the terminal knows it.
        XCTAssertFalse(EcrTransactionType.void.requiresAmount)
        XCTAssertTrue(EcrTransactionType.void.requiresOriginalStan)
        XCTAssertFalse(EcrTransactionType.void.requiresOriginalDate)

        XCTAssertTrue(EcrTransactionType.refund.requiresAmount)
        XCTAssertTrue(EcrTransactionType.refund.requiresOriginalStan)
        XCTAssertTrue(EcrTransactionType.refund.requiresOriginalDate)

        XCTAssertTrue(EcrTransactionType.sale.movesMoney)
        XCTAssertTrue(EcrTransactionType.void.movesMoney)
        XCTAssertTrue(EcrTransactionType.refund.movesMoney)
        XCTAssertFalse(EcrTransactionType.inquiry.movesMoney)
        XCTAssertFalse(EcrTransactionType.receipt.movesMoney)
    }
}
