import Foundation
import AmwalECR

/// The name each SDK failure crosses the channel under.
///
/// The SDK has five failures; the contract has seven kinds, the other two being
/// raised by this wrapper before anything is sent. Kept here rather than in
/// AmwalECR because the channel contract is the wrapper's, and a native app
/// using the SDK directly has no channel to name anything for.
extension EcrFailure {
    var kind: String {
        switch self {
        case .unreachable: return EcrFailureKinds.unreachable
        case .timeout: return EcrFailureKinds.timeout
        case .malformed: return EcrFailureKinds.malformed
        case .connectionLost: return EcrFailureKinds.connectionLost
        case .unauthenticated: return EcrFailureKinds.unauthenticated
        }
    }
}

/// The name a next step crosses the channel under.
///
/// The SDK's own raw value, which is the protocol's — no translation, so there
/// is one spelling to keep in step rather than four.
extension EcrNextStep {
    var channelName: String { rawValue }
}

/// Trimming, as the SDK does it internally — repeated here because the SDK
/// keeps its own copy `internal` rather than adding an extension on `String`
/// to every app that links it.
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Turns channel arguments into SDK types, and SDK types back into the maps the
/// Dart side reads.
///
/// The mirror of `EcrMapping.kt`. Free of Flutter types so it can be tested
/// without a binding.
enum EcrMapping {

    /// Reads the `config` sub-map.
    ///
    /// Every value is optional and falls back to the default, so a Dart side
    /// that gains a setting this host has not been rebuilt for keeps working
    /// rather than failing on an unknown key.
    static func config(_ raw: [String: Any]?) -> EcrConfig {
        var config = EcrConfig()
        guard let raw = raw else { return config }

        if let ecrId = raw[EcrConfigKeys.ecrId] as? String, !ecrId.isEmpty {
            config.ecrId = ecrId
        }
        if let currency = raw[EcrConfigKeys.currencyCode] as? String, !currency.isEmpty {
            config.currencyCode = currency
        }
        if let digits = raw[EcrConfigKeys.minorUnitDigits] as? NSNumber {
            config.minorUnitDigits = digits.intValue
        }
        if let port = raw[EcrConfigKeys.port] as? NSNumber {
            config.port = port.intValue
        }
        if let ms = raw[EcrConfigKeys.connectTimeoutMs] as? NSNumber {
            config.connectTimeout = ms.doubleValue / 1000
        }
        if let ms = raw[EcrConfigKeys.responseTimeoutMs] as? NSNumber {
            config.responseTimeout = ms.doubleValue / 1000
        }
        if let ms = raw[EcrConfigKeys.probeTimeoutMs] as? NSNumber {
            config.probeTimeout = ms.doubleValue / 1000
        }
        // Empty means unsigned, which is a real setting rather than a missing
        // one — so an empty string is taken as given here, unlike the values
        // above.
        if let key = raw[EcrConfigKeys.secureHashKey] as? String {
            config.secureHashKey = key
        }
        if let auto = raw[EcrConfigKeys.autoInquireOnFailure] as? NSNumber,
           CFGetTypeID(auto) == CFBooleanGetTypeID() {
            config.autoInquireOnFailure = auto.boolValue
        }
        return config
    }

    /// Reads the amount, which crosses as a decimal string in major units.
    ///
    /// Never a double, for the same reason the Kotlin host refuses one: the
    /// channel would carry `1.234` as 1.23399999999999998578914528…, which
    /// rounds to the right figure today and the wrong one the day a currency
    /// has four decimal places.
    static func amount(_ raw: Any?) throws -> Decimal? {
        guard let text = (raw as? String)?.trimmed, !text.isEmpty else { return nil }
        guard let value = EcrDecimal.parse(text) else {
            throw EcrInvalidArgument("\"\(text)\" is not a decimal amount")
        }
        return value
    }

    static func result(_ result: EcrResult) -> [String: Any] {
        switch result {
        case let .approved(approved):
            return [
                EcrResultKeys.outcome: EcrOutcomes.approved,
                EcrResultKeys.merchantReferenceId: approved.merchantReferenceId,
                EcrResultKeys.amount: approved.amount,
                EcrResultKeys.responseCode: approved.responseCode,
                EcrResultKeys.rrn: approved.rrn,
                EcrResultKeys.authCode: approved.authCode,
                EcrResultKeys.maskedPan: approved.maskedPan,
                EcrResultKeys.partialApproval: approved.partialApproval,
                EcrResultKeys.requestedAmount: approved.requestedAmount,
                EcrResultKeys.raw: approved.raw,
            ]

        case let .declined(declined):
            return [
                EcrResultKeys.outcome: EcrOutcomes.declined,
                EcrResultKeys.merchantReferenceId: declined.merchantReferenceId,
                EcrResultKeys.responseCode: declined.responseCode,
                EcrResultKeys.reason: declined.reason,
                EcrResultKeys.nextStep: declined.nextStep.channelName,
                EcrResultKeys.raw: declined.raw,
            ]

        case let .failed(reference, failure, recovered):
            var map: [String: Any] = [
                EcrResultKeys.outcome: EcrOutcomes.failed,
                EcrResultKeys.merchantReferenceId: reference,
                EcrResultKeys.failure: self.failure(failure),
            ]
            // Left out rather than sent as null when nothing was asked: the Dart
            // side reads absence as "no follow-up was made", which is not the
            // same as "the follow-up found nothing".
            if let recovered = recovered {
                map[EcrResultKeys.recovered] = self.inquiry(recovered)
            }
            return map
        }
    }

    static func inquiry(_ inquiry: EcrInquiry) -> [String: Any] {
        switch inquiry {
        case let .found(reference, transaction, raw):
            return [
                EcrResultKeys.outcome: EcrOutcomes.found,
                EcrResultKeys.merchantReferenceId: reference,
                EcrResultKeys.transaction: self.transaction(transaction),
                EcrResultKeys.raw: raw,
            ]

        case let .notFound(reference, reason, raw):
            return [
                EcrResultKeys.outcome: EcrOutcomes.notFound,
                EcrResultKeys.merchantReferenceId: reference,
                EcrResultKeys.reason: reason,
                EcrResultKeys.raw: raw,
            ]

        case let .failed(reference, failure):
            return [
                EcrResultKeys.outcome: EcrOutcomes.failed,
                EcrResultKeys.merchantReferenceId: reference,
                EcrResultKeys.failure: self.failure(failure),
            ]
        }
    }

    static func receipt(_ receipt: EcrReceipt) -> [String: Any] {
        switch receipt {
        case let .ready(reference, url, raw):
            return [
                EcrResultKeys.outcome: EcrOutcomes.ready,
                EcrResultKeys.merchantReferenceId: reference,
                EcrResultKeys.url: url,
                EcrResultKeys.raw: raw,
            ]

        case let .unavailable(reference, reason, raw):
            return [
                EcrResultKeys.outcome: EcrOutcomes.unavailable,
                EcrResultKeys.merchantReferenceId: reference,
                EcrResultKeys.reason: reason,
                EcrResultKeys.raw: raw,
            ]

        case let .failed(reference, failure):
            return [
                EcrResultKeys.outcome: EcrOutcomes.failed,
                EcrResultKeys.merchantReferenceId: reference,
                EcrResultKeys.failure: self.failure(failure),
            ]
        }
    }

    static func transaction(_ transaction: EcrTransaction) -> [String: Any] {
        [
            EcrTransactionKeys.transactionId: transaction.transactionId,
            EcrTransactionKeys.stan: transaction.stan,
            EcrTransactionKeys.type: transaction.type,
            EcrTransactionKeys.status: transaction.status,
            EcrTransactionKeys.amount: transaction.amount,
            EcrTransactionKeys.totalAmount: transaction.totalAmount,
            EcrTransactionKeys.currency: transaction.currency,
            EcrTransactionKeys.transactionTime: transaction.transactionTime,
            EcrTransactionKeys.maskedPan: transaction.maskedPan,
            EcrTransactionKeys.cardHolderName: transaction.cardHolderName,
            EcrTransactionKeys.rrn: transaction.rrn,
            EcrTransactionKeys.authCode: transaction.authCode,
            EcrTransactionKeys.batchId: transaction.batchId,
            EcrTransactionKeys.terminalId: transaction.terminalId,
            EcrTransactionKeys.isRefunded: transaction.isRefunded,
            EcrTransactionKeys.canVoid: transaction.canVoid,
            EcrTransactionKeys.canRefund: transaction.canRefund,
        ]
    }

    static func failure(_ failure: EcrFailure) -> [String: Any] {
        [
            EcrFailureKeys.kind: failure.kind,
            EcrFailureKeys.message: failure.message,
        ]
    }

    /// A failure this wrapper raised, which the terminal has no case for.
    static func wrapperFailure(kind: String, message: String) -> [String: Any] {
        [EcrFailureKeys.kind: kind, EcrFailureKeys.message: message]
    }

    /// A result carrying a wrapper-level failure.
    ///
    /// The reference is empty because nothing reached the terminal, or reached
    /// it and was abandoned before it could name itself.
    static func failedResult(kind: String, message: String) -> [String: Any] {
        [
            EcrResultKeys.outcome: EcrOutcomes.failed,
            EcrResultKeys.merchantReferenceId: "",
            EcrResultKeys.failure: wrapperFailure(kind: kind, message: message),
        ]
    }
}
