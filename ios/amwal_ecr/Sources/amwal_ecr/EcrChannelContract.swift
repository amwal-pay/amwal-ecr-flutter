import Foundation

/// The platform-channel contract, mirroring
/// `lib/src/platform/ecr_channel_contract.dart` string for string.
///
/// The third copy of the same document — Dart, Kotlin, Swift. A channel has no
/// shared type system, so the only thing holding the three together is a test
/// on each side asserting these values against frozen literals.
enum EcrMethods {
    static let isReachable = "isReachable"
    static let sale = "sale"
    static let void_ = "void"
    static let refund = "refund"
    static let inquire = "inquire"
    static let inquireByReference = "inquireByReference"
    static let receipt = "receipt"
    static let cancel = "cancel"
}

enum EcrArgs {
    static let operationId = "operationId"
    static let host = "host"
    static let serialNumber = "serialNumber"
    static let transport = "transport"
    static let config = "config"
    static let amount = "amount"
    static let receiptNumber = "receiptNumber"
    static let transactionDate = "transactionDate"
    static let originalTerminalId = "originalTerminalId"
    static let merchantReferenceId = "merchantReferenceId"
    static let originalMerchantReference = "originalMerchantReference"
}

enum EcrConfigKeys {
    static let ecrId = "ecrId"
    static let currencyCode = "currencyCode"
    static let minorUnitDigits = "minorUnitDigits"
    static let port = "port"
    static let connectTimeoutMs = "connectTimeoutMs"
    static let responseTimeoutMs = "responseTimeoutMs"
    static let probeTimeoutMs = "probeTimeoutMs"
    static let secureHashKey = "secureHashKey"
    static let autoInquireOnFailure = "autoInquireOnFailure"
}

enum EcrResultKeys {
    static let outcome = "outcome"
    static let merchantReferenceId = "merchantReferenceId"
    static let amount = "amount"
    static let responseCode = "responseCode"
    static let reason = "reason"
    static let rrn = "rrn"
    static let authCode = "authCode"
    static let maskedPan = "maskedPan"
    static let partialApproval = "partialApproval"
    static let requestedAmount = "requestedAmount"
    static let raw = "raw"
    static let failure = "failure"
    static let transaction = "transaction"
    static let url = "url"
    static let nextStep = "nextStep"
    static let recovered = "recovered"
}

enum EcrOutcomes {
    static let approved = "approved"
    static let declined = "declined"
    static let failed = "failed"
    static let found = "found"
    static let notFound = "notFound"
    static let ready = "ready"
    static let unavailable = "unavailable"
}

enum EcrFailureKeys {
    static let kind = "kind"
    static let message = "message"
}

enum EcrFailureKinds {
    static let unreachable = "unreachable"
    static let timeout = "timeout"
    static let malformed = "malformed"
    static let connectionLost = "connectionLost"
    static let unauthenticated = "unauthenticated"
    static let cancelled = "cancelled"
    static let unsupported = "unsupported"
}

/// Values of `EcrResultKeys.nextStep`.
///
/// The protocol's own spelling, which is also the SDK's enum name — one word for
/// one meaning across the terminal, both native SDKs and the channel.
enum EcrNextSteps {
    static let none = "NONE"
    static let inquireByMerchantReference = "INQUIRE_BY_MERCHANT_REFERENCE"
}

enum EcrTransactionKeys {
    static let transactionId = "transactionId"
    static let stan = "stan"
    static let type = "type"
    static let status = "status"
    static let amount = "amount"
    static let totalAmount = "totalAmount"
    static let currency = "currency"
    static let transactionTime = "transactionTime"
    static let maskedPan = "maskedPan"
    static let cardHolderName = "cardHolderName"
    static let rrn = "rrn"
    static let authCode = "authCode"
    static let batchId = "batchId"
    static let terminalId = "terminalId"
    static let isRefunded = "isRefunded"
    static let canVoid = "canVoid"
    static let canRefund = "canRefund"
}

enum EcrErrorCodes {
    static let invalidArgument = "ecr_invalid_argument"
    static let internalError = "ecr_internal"
}

let kEcrMethodChannel = "com.amwalpay.ecr/methods"

enum EcrTransports {
    static let ethernet = "ethernet"
    static let wifi = "wifi"
    static let bluetooth = "bluetooth"
    static let webService = "webService"

    /// Whether the terminal opens a socket for this transport.
    static func isIpTransport(_ name: String?) -> Bool {
        name == ethernet || name == wifi
    }
}
