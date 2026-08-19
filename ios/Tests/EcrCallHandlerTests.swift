import XCTest
import AmwalECR
@testable import AmwalEcrBridge

/// What the iOS host does with a call.
///
/// The mirror of `EcrCallHandlerTest.kt`, case for case, because "the two
/// platforms behave the same" is a claim that has to be checked on both sides
/// in the same words. As there, what is really under test is not values but
/// counts: a request sent once, a call answered once.
final class EcrCallHandlerTests: XCTestCase {

    // MARK: - Doubles

    /// Records what it was asked, and answers what it was told to.
    private final class FakeTerminal: EcrTerminalPort {
        var reachable = true
        var result: EcrResult = .approved(
            EcrApproved(
                merchantReferenceId: "A1B2C3D4E5F6",
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
        var inquiry: EcrInquiry = .notFound(merchantReferenceId: "REQ", reason: "nothing", raw: "{}")
        var receiptValue: EcrReceipt = .unavailable(merchantReferenceId: "REQ", reason: "nothing", raw: "{}")

        private let lock = NSLock()
        private var _calls: [String] = []
        var calls: [String] {
            lock.lock(); defer { lock.unlock() }
            return _calls
        }

        var lastAmount: Decimal?
        var lastReceiptNumber: String?
        var lastTransactionDate: String?
        var lastOriginalTerminalId: String?
        var lastMerchantReferenceId: String?
        var lastOriginalReference: String?

        /// Held open so a test can cancel while the terminal has the request.
        var gate: DispatchSemaphore?
        let cancelled = XCTestExpectation(description: "terminal cancelled")

        private func record(_ name: String) {
            lock.lock(); _calls.append(name); lock.unlock()
            gate?.wait()
        }

        func isReachable() -> Bool {
            record("isReachable")
            return reachable
        }

        func sale(amount: Decimal, merchantReferenceId: String) throws -> EcrResult {
            lastAmount = amount
            lastMerchantReferenceId = merchantReferenceId
            record("sale")
            return result
        }

        func void(
            receiptNumber: String,
            originalTerminalId: String,
            merchantReferenceId: String
        ) throws -> EcrResult {
            lastReceiptNumber = receiptNumber
            lastOriginalTerminalId = originalTerminalId
            lastMerchantReferenceId = merchantReferenceId
            record("void")
            return result
        }

        func refund(
            amount: Decimal,
            receiptNumber: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReferenceId: String
        ) throws -> EcrResult {
            lastAmount = amount
            lastReceiptNumber = receiptNumber
            lastTransactionDate = transactionDate
            lastOriginalTerminalId = originalTerminalId
            lastMerchantReferenceId = merchantReferenceId
            record("refund")
            return result
        }

        func inquire(
            receiptNumber: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReferenceId: String
        ) throws -> EcrInquiry {
            lastReceiptNumber = receiptNumber
            lastTransactionDate = transactionDate
            lastMerchantReferenceId = merchantReferenceId
            record("inquire")
            return inquiry
        }

        func inquireByReference(
            _ originalReference: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReferenceId: String
        ) throws -> EcrInquiry {
            lastOriginalReference = originalReference
            lastTransactionDate = transactionDate
            lastMerchantReferenceId = merchantReferenceId
            record("inquireByReference")
            return inquiry
        }

        func receipt(
            receiptNumber: String,
            transactionDate: String,
            originalTerminalId: String,
            merchantReferenceId: String
        ) throws -> EcrReceipt {
            lastReceiptNumber = receiptNumber
            lastTransactionDate = transactionDate
            lastMerchantReferenceId = merchantReferenceId
            record("receipt")
            return receiptValue
        }

        func cancel() {
            gate?.signal()
            cancelled.fulfill()
        }
    }

    /// Records every answer, so a second one is visible rather than lost.
    private final class RecordingReply: EcrReply {
        private let lock = NSLock()
        private var _successes: [Any?] = []
        private var _errors: [(String, String?)] = []
        private var _notImplemented = 0

        let answered = XCTestExpectation(description: "call answered")

        var successes: [Any?] {
            lock.lock(); defer { lock.unlock() }
            return _successes
        }

        var errors: [(String, String?)] {
            lock.lock(); defer { lock.unlock() }
            return _errors
        }

        /// How many times this call was answered. Must never exceed one.
        var answerCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _successes.count + _errors.count + _notImplemented
        }

        func success(_ value: Any?) {
            lock.lock(); _successes.append(value); lock.unlock()
            answered.fulfill()
        }

        func error(code: String, message: String?) {
            lock.lock(); _errors.append((code, message)); lock.unlock()
            answered.fulfill()
        }

        func notImplemented() {
            lock.lock(); _notImplemented += 1; lock.unlock()
            answered.fulfill()
        }

        func result() -> [String: Any] {
            successes.compactMap { $0 as? [String: Any] }.first ?? [:]
        }
    }

    // MARK: - Helpers

    private func args(
        operationId: String = "op-1",
        transport: String = "wifi",
        amount: String? = "1.234",
        receiptNumber: String = "",
        transactionDate: String = "",
        originalTerminalId: String = ""
    ) -> [String: Any] {
        var map: [String: Any] = [
            EcrArgs.operationId: operationId,
            EcrArgs.host: "192.168.1.50",
            EcrArgs.serialNumber: "P653200085189",
            EcrArgs.transport: transport,
            EcrArgs.config: [
                EcrConfigKeys.ecrId: "TILL7",
                EcrConfigKeys.currencyCode: "512",
                EcrConfigKeys.minorUnitDigits: 3,
                EcrConfigKeys.port: 9100,
                EcrConfigKeys.connectTimeoutMs: 10_000,
                EcrConfigKeys.responseTimeoutMs: 120_000,
                EcrConfigKeys.probeTimeoutMs: 3_000,
            ],
            EcrArgs.receiptNumber: receiptNumber,
            EcrArgs.transactionDate: transactionDate,
            EcrArgs.originalTerminalId: originalTerminalId,
        ]
        if let amount = amount { map[EcrArgs.amount] = amount }
        return map
    }

    private func handler(for terminal: EcrTerminalPort) -> EcrCallHandler {
        EcrCallHandler { _, _, _ in terminal }
    }

    // MARK: - Tests

    func testASaleIsSentOnceAndAnsweredOnce() {
        let terminal = FakeTerminal()
        let reply = RecordingReply()

        handler(for: terminal).handle(method: EcrMethods.sale, arguments: args(), reply: reply)
        wait(for: [reply.answered], timeout: 2)

        XCTAssertEqual(["sale"], terminal.calls)
        XCTAssertEqual(1, reply.answerCount)
        XCTAssertEqual(EcrOutcomes.approved, reply.result()[EcrResultKeys.outcome] as? String)
    }

    func testTheAmountArrivesAsAnExactDecimalNotADouble() {
        let terminal = FakeTerminal()
        let reply = RecordingReply()

        handler(for: terminal).handle(
            method: EcrMethods.sale,
            arguments: args(amount: "1.234"),
            reply: reply
        )
        wait(for: [reply.answered], timeout: 2)

        // Decimal("1.234"), not the nearest binary double to it.
        XCTAssertEqual(Decimal(string: "1.234"), terminal.lastAmount)
    }

    func testAnAmountThatIsNotADecimalIsRefusedBeforeAnythingIsSent() {
        let terminal = FakeTerminal()
        let reply = RecordingReply()

        handler(for: terminal).handle(
            method: EcrMethods.sale,
            arguments: args(amount: "1,234"),
            reply: reply
        )

        XCTAssertTrue(terminal.calls.isEmpty)
        XCTAssertEqual(1, reply.answerCount)
        XCTAssertEqual(EcrErrorCodes.invalidArgument, reply.errors.first?.0)
    }

    func testASaleWithNoAmountIsRefusedBeforeAnythingIsSent() {
        let terminal = FakeTerminal()
        let reply = RecordingReply()

        handler(for: terminal).handle(
            method: EcrMethods.sale,
            arguments: args(amount: nil),
            reply: reply
        )

        XCTAssertTrue(terminal.calls.isEmpty)
        XCTAssertEqual(EcrErrorCodes.invalidArgument, reply.errors.first?.0)
    }

    func testAVoidCarriesTheReceiptNumberAndTheOtherTerminal() {
        let terminal = FakeTerminal()
        let reply = RecordingReply()

        handler(for: terminal).handle(
            method: EcrMethods.void_,
            arguments: args(amount: nil, receiptNumber: "215", originalTerminalId: "31629"),
            reply: reply
        )
        wait(for: [reply.answered], timeout: 2)

        XCTAssertEqual("215", terminal.lastReceiptNumber)
        XCTAssertEqual("31629", terminal.lastOriginalTerminalId)
    }

    func testAVoidWithNoReceiptNumberIsRefusedBeforeAnythingIsSent() {
        let terminal = FakeTerminal()
        let reply = RecordingReply()

        handler(for: terminal).handle(
            method: EcrMethods.void_,
            arguments: args(amount: nil, receiptNumber: "   "),
            reply: reply
        )

        XCTAssertTrue(terminal.calls.isEmpty)
        XCTAssertEqual(EcrErrorCodes.invalidArgument, reply.errors.first?.0)
    }

    func testARefundCarriesAmountReceiptNumberAndTheOriginalDay() {
        let terminal = FakeTerminal()
        let reply = RecordingReply()

        handler(for: terminal).handle(
            method: EcrMethods.refund,
            arguments: args(amount: "0.216", receiptNumber: "208", transactionDate: "20260809"),
            reply: reply
        )
        wait(for: [reply.answered], timeout: 2)

        XCTAssertEqual(Decimal(string: "0.216"), terminal.lastAmount)
        XCTAssertEqual("208", terminal.lastReceiptNumber)
        XCTAssertEqual("20260809", terminal.lastTransactionDate)
    }

    func testATransportWithNoListenerIsRefusedWithoutTouchingTheTerminal() {
        for transport in ["bluetooth", "webService"] {
            let terminal = FakeTerminal()
            let reply = RecordingReply()

            handler(for: terminal).handle(
                method: EcrMethods.sale,
                arguments: args(transport: transport),
                reply: reply
            )

            XCTAssertTrue(terminal.calls.isEmpty, transport)
            XCTAssertEqual(1, reply.answerCount, transport)
            let failure = reply.result()[EcrResultKeys.failure] as? [String: Any]
            XCTAssertEqual(EcrFailureKinds.unsupported, failure?[EcrFailureKeys.kind] as? String)
        }
    }

    func testIsReachableOverATransportWithNoListenerIsFalseNotAProbe() {
        let terminal = FakeTerminal()
        let reply = RecordingReply()

        handler(for: terminal).handle(
            method: EcrMethods.isReachable,
            arguments: args(transport: "bluetooth"),
            reply: reply
        )

        XCTAssertTrue(terminal.calls.isEmpty)
        XCTAssertEqual(false, reply.successes.first as? Bool)
    }

    func testAnUnknownMethodIsReportedAsNotImplementedOnce() {
        let reply = RecordingReply()

        handler(for: FakeTerminal()).handle(
            method: "teleport",
            arguments: args(),
            reply: reply
        )

        XCTAssertEqual(1, reply.answerCount)
    }

    func testACallWithNoArgumentsIsRefusedRatherThanCrashing() {
        let reply = RecordingReply()

        handler(for: FakeTerminal()).handle(
            method: EcrMethods.sale,
            arguments: nil,
            reply: reply
        )

        XCTAssertEqual(EcrErrorCodes.invalidArgument, reply.errors.first?.0)
    }

    func testCancellingNamesTheOperationAndAnswersItAsCancelled() {
        let terminal = FakeTerminal()
        terminal.gate = DispatchSemaphore(value: 0)
        let handler = self.handler(for: terminal)
        let reply = RecordingReply()

        handler.handle(method: EcrMethods.sale, arguments: args(operationId: "till-9"), reply: reply)

        // Wait for the operation to be registered and the terminal to be busy.
        let registered = XCTestExpectation(description: "in flight")
        DispatchQueue.global().async {
            while handler.inFlightCount == 0 || terminal.calls.isEmpty { usleep(1_000) }
            registered.fulfill()
        }
        wait(for: [registered], timeout: 2)

        let cancelReply = RecordingReply()
        handler.handle(
            method: EcrMethods.cancel,
            arguments: [EcrArgs.operationId: "till-9"],
            reply: cancelReply
        )

        XCTAssertEqual(true, cancelReply.successes.first as? Bool)
        wait(for: [terminal.cancelled], timeout: 2)

        let failure = reply.result()[EcrResultKeys.failure] as? [String: Any]
        XCTAssertEqual(EcrFailureKinds.cancelled, failure?[EcrFailureKeys.kind] as? String)
        XCTAssertTrue(
            (failure?[EcrFailureKeys.message] as? String)?
                .contains("inquire before retrying") == true
        )

        // The terminal answers late. The call has already been answered, so the
        // reply is dropped rather than delivered a second time.
        wait(for: [reply.answered], timeout: 2)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(1, reply.answerCount)
        // And nothing was sent again.
        XCTAssertEqual(["sale"], terminal.calls)
    }

    func testCancellingAnOperationThatAlreadyAnsweredSaysNothingWasRunning() {
        let handler = self.handler(for: FakeTerminal())
        let reply = RecordingReply()

        handler.handle(method: EcrMethods.sale, arguments: args(operationId: "till-9"), reply: reply)
        wait(for: [reply.answered], timeout: 2)
        Thread.sleep(forTimeInterval: 0.1)

        let cancelReply = RecordingReply()
        handler.handle(
            method: EcrMethods.cancel,
            arguments: [EcrArgs.operationId: "till-9"],
            reply: cancelReply
        )

        XCTAssertEqual(false, cancelReply.successes.first as? Bool)
    }

    func testAnOperationIsDeregisteredOnceItAnswers() {
        let handler = self.handler(for: FakeTerminal())
        let reply = RecordingReply()

        handler.handle(method: EcrMethods.sale, arguments: args(), reply: reply)
        wait(for: [reply.answered], timeout: 2)
        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertEqual(0, handler.inFlightCount)
    }

    func testADeclinedSaleIsReportedAsDeclinedWithTheTerminalsWords() {
        let terminal = FakeTerminal()
        terminal.result = .declined(
            EcrDeclined(merchantReferenceId: "REQ", responseCode: "51", reason: "Insufficient funds", raw: "{}")
        )
        let reply = RecordingReply()

        handler(for: terminal).handle(method: EcrMethods.sale, arguments: args(), reply: reply)
        wait(for: [reply.answered], timeout: 2)

        let result = reply.result()
        XCTAssertEqual(EcrOutcomes.declined, result[EcrResultKeys.outcome] as? String)
        XCTAssertEqual("51", result[EcrResultKeys.responseCode] as? String)
        XCTAssertEqual("Insufficient funds", result[EcrResultKeys.reason] as? String)
    }

    func testATimeoutIsReportedAsAFailureNeverAsADecline() {
        let terminal = FakeTerminal()
        terminal.result = .failed(merchantReferenceId: "REQ", failure: .timeout("no answer in 120s"), recovered: nil)
        let reply = RecordingReply()

        handler(for: terminal).handle(method: EcrMethods.sale, arguments: args(), reply: reply)
        wait(for: [reply.answered], timeout: 2)

        let result = reply.result()
        XCTAssertEqual(EcrOutcomes.failed, result[EcrResultKeys.outcome] as? String)
        let failure = result[EcrResultKeys.failure] as? [String: Any]
        XCTAssertEqual(EcrFailureKinds.timeout, failure?[EcrFailureKeys.kind] as? String)
    }

    func testAnInquiryAnswersWithItsOwnShapeNotASales() {
        let terminal = FakeTerminal()
        terminal.inquiry = .found(
            merchantReferenceId: "REQ",
            transaction: EcrTransaction(
                transactionId: "e970c800",
                stan: "000208",
                type: "Purchase",
                status: "Approved",
                amount: "0.258",
                totalAmount: "0.258",
                currency: "OMR",
                transactionTime: "2026-08-09T16:58:16",
                maskedPan: "543173******5785",
                cardHolderName: "",
                rrn: "78628029647",
                authCode: "",
                batchId: "00000003",
                terminalId: "31629",
                isRefunded: false,
                canVoid: true,
                canRefund: true
            ),
            raw: "{}"
        )
        let reply = RecordingReply()

        handler(for: terminal).handle(
            method: EcrMethods.inquire,
            arguments: args(amount: nil, receiptNumber: "208", transactionDate: "20260809"),
            reply: reply
        )
        wait(for: [reply.answered], timeout: 2)

        let result = reply.result()
        XCTAssertEqual(EcrOutcomes.found, result[EcrResultKeys.outcome] as? String)
        let transaction = result[EcrResultKeys.transaction] as? [String: Any]
        XCTAssertEqual("000208", transaction?[EcrTransactionKeys.stan] as? String)
        XCTAssertEqual("Approved", transaction?[EcrTransactionKeys.status] as? String)
        XCTAssertEqual(true, transaction?[EcrTransactionKeys.canVoid] as? Bool)
    }

    func testAReceiptAnswersWithItsOwnShapeToo() {
        let terminal = FakeTerminal()
        terminal.receiptValue = .ready(
            merchantReferenceId: "REQ",
            url: "https://example.test/r/1",
            raw: "{}"
        )
        let reply = RecordingReply()

        handler(for: terminal).handle(
            method: EcrMethods.receipt,
            arguments: args(amount: nil, receiptNumber: "215", transactionDate: "20260809"),
            reply: reply
        )
        wait(for: [reply.answered], timeout: 2)

        let result = reply.result()
        XCTAssertEqual(EcrOutcomes.ready, result[EcrResultKeys.outcome] as? String)
        XCTAssertEqual("https://example.test/r/1", result[EcrResultKeys.url] as? String)
    }

    func testNothingIsEverSentTwiceWhateverTheOutcome() {
        let outcomes: [EcrResult] = [
            .declined(EcrDeclined(merchantReferenceId: "REQ", responseCode: "51", reason: "no", raw: "{}")),
            .failed(merchantReferenceId: "REQ", failure: .timeout("no answer"), recovered: nil),
            .failed(merchantReferenceId: "REQ", failure: .unreachable("no route"), recovered: nil),
            .failed(merchantReferenceId: "REQ", failure: .connectionLost("closed"), recovered: nil),
            .failed(merchantReferenceId: "REQ", failure: .malformed("not JSON"), recovered: nil),
        ]

        for outcome in outcomes {
            let terminal = FakeTerminal()
            terminal.result = outcome
            let reply = RecordingReply()

            handler(for: terminal).handle(method: EcrMethods.sale, arguments: args(), reply: reply)
            wait(for: [reply.answered], timeout: 2)

            XCTAssertEqual(["sale"], terminal.calls)
            XCTAssertEqual(1, reply.answerCount)
        }
    }

    func testAOneShotReplyLetsTheFirstAnswerThroughAndDropsTheRest() {
        let inner = RecordingReply()
        let reply = OneShotReply(inner)

        reply.success("first")
        reply.success("second")
        reply.error(code: "code", message: "message")

        XCTAssertEqual(1, inner.answerCount)
        XCTAssertEqual("first", inner.successes.first as? String)
        XCTAssertTrue(reply.hasAnswered)
    }

    func testAOneShotReplyThatErroredFirstStaysErrored() {
        let inner = RecordingReply()
        let reply = OneShotReply(inner)

        reply.error(code: "code", message: "message")
        reply.success("late")

        XCTAssertEqual(1, inner.answerCount)
        XCTAssertEqual("code", inner.errors.first?.0)
    }

    func testTheConfigCrossesWithMillisecondsBecomingSeconds() {
        let config = EcrMapping.config([
            EcrConfigKeys.ecrId: "TILL7",
            EcrConfigKeys.currencyCode: "840",
            EcrConfigKeys.minorUnitDigits: 2,
            EcrConfigKeys.port: 9200,
            EcrConfigKeys.connectTimeoutMs: 5_000,
            EcrConfigKeys.responseTimeoutMs: 90_000,
            EcrConfigKeys.probeTimeoutMs: 1_500,
        ])

        XCTAssertEqual("TILL7", config.ecrId)
        XCTAssertEqual("840", config.currencyCode)
        XCTAssertEqual(2, config.minorUnitDigits)
        XCTAssertEqual(9200, config.port)
        XCTAssertEqual(5, config.connectTimeout)
        XCTAssertEqual(90, config.responseTimeout)
        XCTAssertEqual(1.5, config.probeTimeout)
    }

    func testAMissingConfigFallsBackToTheDefaults() {
        let defaults = EcrConfig()
        let config = EcrMapping.config(nil)

        // A Dart side that gains a setting this host was not rebuilt for keeps
        // working rather than failing on an unknown key.
        XCTAssertEqual(defaults.ecrId, config.ecrId)
        XCTAssertEqual(defaults.port, config.port)
        XCTAssertEqual(defaults.minorUnitDigits, config.minorUnitDigits)
        XCTAssertEqual(defaults.responseTimeout, config.responseTimeout)
    }

    func testAFailureMapsToItsChannelKind() {
        XCTAssertEqual(
            EcrFailureKinds.unreachable,
            EcrMapping.failure(.unreachable("x"))[EcrFailureKeys.kind] as? String
        )
        XCTAssertEqual(
            EcrFailureKinds.timeout,
            EcrMapping.failure(.timeout("x"))[EcrFailureKeys.kind] as? String
        )
        XCTAssertEqual(
            EcrFailureKinds.malformed,
            EcrMapping.failure(.malformed("x"))[EcrFailureKeys.kind] as? String
        )
        XCTAssertEqual(
            EcrFailureKinds.connectionLost,
            EcrMapping.failure(.connectionLost("x"))[EcrFailureKeys.kind] as? String
        )
    }
}
