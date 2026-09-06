import XCTest
import AmwalECR
@testable import AmwalEcrBridge

/// What the iOS host does with the 1.0.4 additions.
///
/// The mirror of the Kotlin host's `EcrReferenceAndSigningTest`, and of the Dart
/// side's `reference_and_signing_test.dart`. All three assert the same things in
/// the same words, because "the two platforms behave the same" is a claim that
/// has to be checked on both sides rather than asserted in a document.
///
/// This is the mapping, not the protocol: signing itself is the SDK's, and is
/// tested in `ios-sdk/Tests/AmwalECRTests/SecureHashTests.swift`. What matters
/// here is that nothing is dropped on the way across the channel.
final class EcrReferenceAndSigningTests: XCTestCase {

    private let key = "881dc200c9833da726e9376c2e32cff7"

    // MARK: - Doubles

    /// Answers what it is told to, and remembers what it was asked.
    private final class SpyTerminal: EcrTerminalPort {
        var result: EcrResult = .failed(
            merchantReference: "REQ",
            failure: .timeout("no answer"),
            recovered: nil
        )
        var inquiry: EcrInquiry = .notFound(
            merchantReference: "REQ",
            reason: "nothing",
            raw: "{}"
        )

        private(set) var calls: [String] = []
        var config: EcrConfig?
        private(set) var lastMerchantReference: String?
        private(set) var lastOriginalReference: String?
        private(set) var lastTransactionDate: String?

        init(config: EcrConfig? = nil) { self.config = config }

        func isReachable() -> Bool { true }

        func probeReachability() -> EcrReachability {
            EcrReachability(reachable: true, host: "127.0.0.1", port: 9100)
        }

        func sale(amount: Decimal, merchantReference: String) throws -> EcrResult {
            calls.append("sale")
            lastMerchantReference = merchantReference
            return result
        }

        func void(
            receiptNumber: String,
            originalTerminalId: String,
            merchantReference: String
        ) throws -> EcrResult {
            calls.append("void")
            lastMerchantReference = merchantReference
            return result
        }

        func refund(
            amount: Decimal,
            receiptNumber: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReference: String
        ) throws -> EcrResult {
            calls.append("refund")
            lastMerchantReference = merchantReference
            return result
        }

        func inquire(
            receiptNumber: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReference: String
        ) throws -> EcrInquiry {
            calls.append("inquire")
            lastMerchantReference = merchantReference
            return inquiry
        }

        func inquireByReference(
            _ originalReference: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReference: String
        ) throws -> EcrInquiry {
            calls.append("inquireByReference")
            lastOriginalReference = originalReference
            lastTransactionDate = transactionDate
            lastMerchantReference = merchantReference
            return inquiry
        }

        func receipt(
            receiptNumber: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReference: String
        ) throws -> EcrReceipt {
            calls.append("receipt")
            lastMerchantReference = merchantReference
            return .unavailable(merchantReference: "REQ", reason: "no", raw: "{}")
        }

        func cancel() {}
    }

    private final class Recorder: EcrReply {
        let answered = XCTestExpectation(description: "call answered")
        private(set) var value: [String: Any] = [:]
        private(set) var errors: [(String, String?)] = []

        func success(_ value: Any?) {
            self.value = value as? [String: Any] ?? [:]
            answered.fulfill()
        }

        func error(code: String, message: String?) {
            errors.append((code, message))
            answered.fulfill()
        }

        func notImplemented() { answered.fulfill() }
    }

    // MARK: - Helpers

    private func args(
        merchantReference: String = "",
        originalMerchantReference: String = "",
        transactionDate: String = "",
        secureHashKey: String = "",
        autoInquireOnFailure: Bool = true
    ) -> [String: Any] {
        [
            EcrArgs.operationId: "op-1",
            EcrArgs.host: "192.168.1.50",
            EcrArgs.serialNumber: "P653200085189",
            EcrArgs.transport: EcrTransports.wifi,
            EcrArgs.amount: "1.234",
            EcrArgs.receiptNumber: "215",
            EcrArgs.transactionDate: transactionDate,
            EcrArgs.originalTerminalId: "",
            EcrArgs.merchantReference: merchantReference,
            EcrArgs.originalMerchantReference: originalMerchantReference,
            EcrArgs.config: [
                EcrConfigKeys.ecrId: "TILL7",
                EcrConfigKeys.currencyCode: "512",
                EcrConfigKeys.minorUnitDigits: 3,
                EcrConfigKeys.port: 9100,
                EcrConfigKeys.connectTimeoutMs: 10_000,
                EcrConfigKeys.responseTimeoutMs: 120_000,
                EcrConfigKeys.probeTimeoutMs: 3_000,
                EcrConfigKeys.secureHashKey: secureHashKey,
                EcrConfigKeys.autoInquireOnFailure: autoInquireOnFailure,
            ],
        ]
    }

    /// Runs one call and returns the map the Dart side would receive.
    @discardableResult
    private func call(
        _ method: String,
        _ arguments: [String: Any],
        terminal: SpyTerminal
    ) -> [String: Any] {
        let reply = Recorder()
        let handler = EcrCallHandler { _, _, _, config in
            terminal.config = config
            return terminal
        }
        handler.handle(method: method, arguments: arguments, reply: reply)
        wait(for: [reply.answered], timeout: 2)
        return reply.value
    }

    // MARK: - The shared secret

    func testTheSecretAndTheAutoInquireSettingReachTheSdk() {
        let terminal = SpyTerminal()

        call(EcrMethods.sale, args(secureHashKey: key, autoInquireOnFailure: false),
             terminal: terminal)

        XCTAssertEqual(key, terminal.config?.secureHashKey)
        XCTAssertTrue(terminal.config?.signsMessages ?? false)
        XCTAssertEqual(false, terminal.config?.autoInquireOnFailure)
    }

    func testAnEmptyKeyMeansUnsignedRatherThanMissing() {
        let terminal = SpyTerminal()

        call(EcrMethods.sale, args(), terminal: terminal)

        XCTAssertEqual("", terminal.config?.secureHashKey)
        XCTAssertFalse(terminal.config?.signsMessages ?? true)
        // The default is on, and a host that was not told keeps it.
        XCTAssertEqual(true, terminal.config?.autoInquireOnFailure)
    }

    func testAnUnauthenticatedAnswerCrossesAsItsOwnKindNotAsADecline() {
        // The one reading that must never happen: a till that books this as a
        // refusal will retry, and the cardholder pays twice.
        let terminal = SpyTerminal()
        terminal.result = .failed(
            merchantReference: "ORDER-1",
            failure: .unauthenticated("not signed with this terminal's key"),
            recovered: nil
        )

        let map = call(EcrMethods.sale, args(secureHashKey: key), terminal: terminal)

        XCTAssertEqual(EcrOutcomes.failed, map[EcrResultKeys.outcome] as? String)
        let failure = map[EcrResultKeys.failure] as? [String: Any]
        XCTAssertEqual(EcrFailureKinds.unauthenticated, failure?[EcrFailureKeys.kind] as? String)
    }

    // MARK: - The till's own reference

    func testTheReferenceIsHandedToTheSdkAndReportedBack() {
        let terminal = SpyTerminal()
        terminal.result = .approved(
            EcrApproved(
                merchantReference: "ORDER-4471",
                amount: "1.234",
                responseCode: "00",
                rrn: "622113155340",
                authCode: "517842",
                maskedPan: "543173xxxx5785",
                partialApproval: false,
                requestedAmount: "",
                raw: "{}"
            )
        )

        let map = call(EcrMethods.sale, args(merchantReference: "ORDER-4471"),
                       terminal: terminal)

        XCTAssertEqual("ORDER-4471", terminal.lastMerchantReference)
        XCTAssertEqual("ORDER-4471", map[EcrResultKeys.merchantReference] as? String)
    }

    func testEveryOperationCarriesTheReference() {
        for method in [EcrMethods.sale, EcrMethods.void_, EcrMethods.refund,
                       EcrMethods.inquire, EcrMethods.receipt] {
            let terminal = SpyTerminal()
            call(method, args(merchantReference: "REF-1"), terminal: terminal)
            XCTAssertEqual("REF-1", terminal.lastMerchantReference, method)
        }
    }

    // MARK: - Looking a transaction up by its reference

    func testTheLookupTakesTheOriginalsReferenceNotThisCallsOwn() {
        let terminal = SpyTerminal()

        call(
            EcrMethods.inquireByReference,
            args(merchantReference: "LOOKUP-1", originalMerchantReference: "ORDER-4471"),
            terminal: terminal
        )

        XCTAssertEqual(["inquireByReference"], terminal.calls)
        XCTAssertEqual("ORDER-4471", terminal.lastOriginalReference)
        XCTAssertEqual("LOOKUP-1", terminal.lastMerchantReference)
    }

    func testTheLookupIsRefusedWithoutTheReferenceItLooksUp() {
        let terminal = SpyTerminal()
        let reply = Recorder()

        EcrCallHandler { _, _, _, _ in terminal }
            .handle(method: EcrMethods.inquireByReference, arguments: args(), reply: reply)
        wait(for: [reply.answered], timeout: 2)

        XCTAssertEqual(EcrErrorCodes.invalidArgument, reply.errors.first?.0)
        XCTAssertTrue(terminal.calls.isEmpty, "nothing may be sent")
    }

    // MARK: - What the follow-up found

    func testAFailureThatWasFollowedUpCarriesWhatItFound() {
        let terminal = SpyTerminal()
        terminal.result = .failed(
            merchantReference: "ORDER-4471",
            failure: .timeout("no answer in 120s"),
            recovered: .found(
                merchantReference: "ORDER-4471",
                transaction: transaction(status: "Approved"),
                raw: "{}"
            )
        )

        let map = call(EcrMethods.sale, args(), terminal: terminal)

        let recovered = map[EcrResultKeys.recovered] as? [String: Any]
        XCTAssertEqual(EcrOutcomes.found, recovered?[EcrResultKeys.outcome] as? String)
        let found = recovered?[EcrResultKeys.transaction] as? [String: Any]
        XCTAssertEqual("Approved", found?[EcrTransactionKeys.status] as? String)
    }

    func testNoFollowUpMeansTheKeyIsAbsentRatherThanNull() {
        // The Dart side reads absence as "no follow-up was made", which is not
        // the same as "the follow-up found nothing".
        let terminal = SpyTerminal()
        terminal.result = .failed(
            merchantReference: "ORDER-4471",
            failure: .timeout("no answer"),
            recovered: nil
        )

        let map = call(EcrMethods.sale, args(autoInquireOnFailure: false), terminal: terminal)

        XCTAssertNil(map.index(forKey: EcrResultKeys.recovered))
    }

    // MARK: - What the terminal says to do next

    func testADeclineCarriesTheStepTheTerminalStated() {
        let terminal = SpyTerminal()
        terminal.result = .declined(
            EcrDeclined(
                merchantReference: "ORDER-1",
                responseCode: "05",
                reason: "Do not honour",
                nextStep: .inquireByMerchantReference,
                raw: "{}"
            )
        )

        let map = call(EcrMethods.sale, args(), terminal: terminal)

        XCTAssertEqual(
            EcrNextSteps.inquireByMerchantReference,
            map[EcrResultKeys.nextStep] as? String
        )
    }

    func testAnOrdinaryDeclineSaysNothingFurtherIsNeeded() {
        let terminal = SpyTerminal()
        terminal.result = .declined(
            EcrDeclined(
                merchantReference: "ORDER-1",
                responseCode: "51",
                reason: "Insufficient funds",
                raw: "{}"
            )
        )

        let map = call(EcrMethods.sale, args(), terminal: terminal)

        XCTAssertEqual(EcrNextSteps.none, map[EcrResultKeys.nextStep] as? String)
    }

    private func transaction(status: String) -> EcrTransaction {
        EcrTransaction(
            transactionId: "4471",
            stan: "000215",
            type: "Sale",
            status: status,
            amount: "1.234",
            totalAmount: "1.234",
            currency: "OMR",
            transactionTime: "2026-08-09T12:41:07",
            maskedPan: "543173xxxx5785",
            cardHolderName: "",
            rrn: "622113155340",
            authCode: "517842",
            batchId: "1",
            terminalId: "31629",
            isRefunded: false,
            canVoid: true,
            canRefund: true
        )
    }
}