package com.amwalpay.ecr.flutter

/**
 * The platform-channel contract, mirroring
 * `lib/src/platform/ecr_channel_contract.dart` string for string.
 *
 * The two files are the same document written twice, which is the price of a
 * channel: there is no shared type system across it. `EcrChannelContractTest`
 * asserts these values against frozen literals, and the Dart contract test
 * asserts its own against the same ones, so a rename that lands on one side
 * only fails a test rather than silently going unanswered at a till.
 */
internal object EcrMethods {
    const val IS_REACHABLE = "isReachable"
    const val SALE = "sale"
    const val VOID = "void"
    const val REFUND = "refund"
    const val INQUIRE = "inquire"
    const val INQUIRE_BY_REFERENCE = "inquireByReference"
    const val RECEIPT = "receipt"
    const val CANCEL = "cancel"
}

internal object EcrArgs {
    const val OPERATION_ID = "operationId"
    const val HOST = "host"
    const val SERIAL_NUMBER = "serialNumber"
    const val TRANSPORT = "transport"
    const val CONFIG = "config"
    const val AMOUNT = "amount"
    const val RECEIPT_NUMBER = "receiptNumber"
    const val TRANSACTION_DATE = "transactionDate"
    const val ORIGINAL_TERMINAL_ID = "originalTerminalId"
    const val MERCHANT_REFERENCE_ID = "merchantReferenceId"
    const val ORIGINAL_MERCHANT_REFERENCE = "originalMerchantReference"
}

internal object EcrConfigKeys {
    const val ECR_ID = "ecrId"
    const val CURRENCY_CODE = "currencyCode"
    const val MINOR_UNIT_DIGITS = "minorUnitDigits"
    const val PORT = "port"
    const val CONNECT_TIMEOUT_MS = "connectTimeoutMs"
    const val RESPONSE_TIMEOUT_MS = "responseTimeoutMs"
    const val PROBE_TIMEOUT_MS = "probeTimeoutMs"
    const val SECURE_HASH_KEY = "secureHashKey"
    const val AUTO_INQUIRE_ON_FAILURE = "autoInquireOnFailure"
}

internal object EcrResultKeys {
    const val OUTCOME = "outcome"
    const val MERCHANT_REFERENCE_ID = "merchantReferenceId"
    const val AMOUNT = "amount"
    const val RESPONSE_CODE = "responseCode"
    const val REASON = "reason"
    const val RRN = "rrn"
    const val AUTH_CODE = "authCode"
    const val MASKED_PAN = "maskedPan"
    const val PARTIAL_APPROVAL = "partialApproval"
    const val REQUESTED_AMOUNT = "requestedAmount"
    const val RAW = "raw"
    const val FAILURE = "failure"
    const val TRANSACTION = "transaction"
    const val URL = "url"
    const val NEXT_STEP = "nextStep"
    const val RECOVERED = "recovered"
}

internal object EcrOutcomes {
    const val APPROVED = "approved"
    const val DECLINED = "declined"
    const val FAILED = "failed"
    const val FOUND = "found"
    const val NOT_FOUND = "notFound"
    const val READY = "ready"
    const val UNAVAILABLE = "unavailable"
}

internal object EcrFailureKeys {
    const val KIND = "kind"
    const val MESSAGE = "message"
}

internal object EcrFailureKinds {
    const val UNREACHABLE = "unreachable"
    const val TIMEOUT = "timeout"
    const val MALFORMED = "malformed"
    const val CONNECTION_LOST = "connectionLost"
    const val UNAUTHENTICATED = "unauthenticated"
    const val CANCELLED = "cancelled"
    const val UNSUPPORTED = "unsupported"
}

/**
 * Values of [EcrResultKeys.NEXT_STEP].
 *
 * The protocol's own spelling, which is also the SDK's enum name — one word for
 * one meaning across the terminal, both native SDKs and the channel.
 */
internal object EcrNextSteps {
    const val NONE = "NONE"
    const val INQUIRE_BY_MERCHANT_REFERENCE = "INQUIRE_BY_MERCHANT_REFERENCE"
}

internal object EcrTransactionKeys {
    const val TRANSACTION_ID = "transactionId"
    const val STAN = "stan"
    const val TYPE = "type"
    const val STATUS = "status"
    const val AMOUNT = "amount"
    const val TOTAL_AMOUNT = "totalAmount"
    const val CURRENCY = "currency"
    const val TRANSACTION_TIME = "transactionTime"
    const val MASKED_PAN = "maskedPan"
    const val CARD_HOLDER_NAME = "cardHolderName"
    const val RRN = "rrn"
    const val AUTH_CODE = "authCode"
    const val BATCH_ID = "batchId"
    const val TERMINAL_ID = "terminalId"
    const val IS_REFUNDED = "isRefunded"
    const val CAN_VOID = "canVoid"
    const val CAN_REFUND = "canRefund"
}

internal object EcrErrorCodes {
    const val INVALID_ARGUMENT = "ecr_invalid_argument"
    const val INTERNAL = "ecr_internal"
}

internal const val ECR_METHOD_CHANNEL = "com.amwalpay.ecr/methods"

/** Transport names as the Dart side spells them. */
internal object EcrTransports {
    const val ETHERNET = "ethernet"
    const val WIFI = "wifi"
    const val BLUETOOTH = "bluetooth"
    const val WEB_SERVICE = "webService"

    /** Whether the terminal opens a socket for this transport. */
    fun isIpTransport(name: String?): Boolean = name == ETHERNET || name == WIFI
}
