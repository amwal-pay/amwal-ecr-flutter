/// The platform-channel contract, written down once.
///
/// Every method name and every map key that crosses the channel is named here,
/// and the Kotlin and Swift sides bind to constants that mirror this file
/// character for character (`EcrChannelContract.kt`, `EcrChannelContract.swift`).
/// A rename that misses one of the three is a silent breakage — the call simply
/// stops being answered — so the contract test in
/// `test/platform/channel_contract_test.dart` asserts the Dart side against a
/// frozen literal list, and the native unit tests assert theirs against the
/// same strings.
library;

// Each constant below is a wire name, and its Dart name is the same word. A
// doc comment on `static const String sale = 'sale'` would say "the sale
// method" ninety times over and bury the handful of notes that do carry
// meaning — those are written where they apply.
// ignore_for_file: public_member_api_docs

/// Names of the methods the plugin invokes on the host.
abstract final class EcrMethods {
  /// `isReachable(args) -> bool`
  static const String isReachable = 'isReachable';

  /// `sale(args) -> result map`
  static const String sale = 'sale';

  /// `void(args) -> result map`
  static const String voidTransaction = 'void';

  /// `refund(args) -> result map`
  static const String refund = 'refund';

  /// `inquire(args) -> inquiry map`
  static const String inquire = 'inquire';

  /// `inquireByReference(args) -> inquiry map`
  ///
  /// Looks a transaction up by the reference the till sent it with, rather than
  /// by the receipt number that only arrives in the answer.
  static const String inquireByReference = 'inquireByReference';

  /// `receipt(args) -> receipt map`
  static const String receipt = 'receipt';

  /// `cancel({operationId}) -> bool`, true when an operation was still running.
  static const String cancel = 'cancel';

  /// Every method the contract defines, in the order the API presents them.
  static const List<String> all = <String>[
    isReachable,
    sale,
    voidTransaction,
    refund,
    inquire,
    inquireByReference,
    receipt,
    cancel,
  ];
}

/// Keys in the argument map sent with every call.
abstract final class EcrArgs {
  /// Client-generated handle for this call, so [EcrMethods.cancel] can name it.
  ///
  /// Distinct from [merchantReferenceId], which travels on the wire and names
  /// the transaction to the terminal. This one never leaves the device.
  static const String operationId = 'operationId';

  static const String host = 'host';
  static const String serialNumber = 'serialNumber';
  static const String transport = 'transport';
  static const String config = 'config';

  /// Major units as a decimal string, e.g. `"1.234"`. Never a double: a
  /// binary float cannot hold 1.234, and an amount that is off by a
  /// thousandth is a wrong charge.
  static const String amount = 'amount';

  /// The receipt number (STAN) of the original, unpadded as the operator typed
  /// it. The native side pads it to the protocol's six digits.
  static const String receiptNumber = 'receiptNumber';

  /// The original's day as `yyyyMMdd`.
  static const String transactionDate = 'transactionDate';

  /// The terminal the original was taken on, when not this one. Empty for
  /// "this terminal" — never null, matching the native SDKs' defaults.
  static const String originalTerminalId = 'originalTerminalId';

  /// The till's own reference for this request. Empty to have the native SDK
  /// generate one, which it then reports back on the result.
  static const String merchantReferenceId = 'merchantReferenceId';

  /// The reference an *earlier* transaction was sent with, for
  /// [EcrMethods.inquireByReference]. Never a reference for this call — that is
  /// [merchantReferenceId].
  static const String originalMerchantReference = 'originalMerchantReference';

  static const List<String> all = <String>[
    operationId,
    host,
    serialNumber,
    transport,
    config,
    amount,
    receiptNumber,
    transactionDate,
    originalTerminalId,
    merchantReferenceId,
    originalMerchantReference,
  ];
}

/// Keys inside the `config` sub-map.
///
/// Durations cross as whole milliseconds. `kotlin.time.Duration` and Swift's
/// `TimeInterval` disagree on units and precision, so the channel picks one and
/// both sides convert at the boundary.
abstract final class EcrConfigKeys {
  static const String ecrId = 'ecrId';
  static const String currencyCode = 'currencyCode';
  static const String minorUnitDigits = 'minorUnitDigits';
  static const String port = 'port';
  static const String connectTimeoutMs = 'connectTimeoutMs';
  static const String responseTimeoutMs = 'responseTimeoutMs';
  static const String probeTimeoutMs = 'probeTimeoutMs';

  /// The shared secret as hex, or empty for unsigned messages. Crosses the
  /// channel because the signing happens in the native SDK, where the wire
  /// format lives.
  static const String secureHashKey = 'secureHashKey';

  static const String autoInquireOnFailure = 'autoInquireOnFailure';

  static const List<String> all = <String>[
    ecrId,
    currencyCode,
    minorUnitDigits,
    port,
    connectTimeoutMs,
    responseTimeoutMs,
    probeTimeoutMs,
    secureHashKey,
    autoInquireOnFailure,
  ];
}

/// Keys in the maps the host returns.
abstract final class EcrResultKeys {
  /// Discriminator: which branch of the sealed result this map is.
  static const String outcome = 'outcome';

  /// The reference the transaction was sent with — the caller's own where one
  /// was given, otherwise the one the native SDK generated.
  static const String merchantReferenceId = 'merchantReferenceId';

  static const String amount = 'amount';
  static const String responseCode = 'responseCode';
  static const String responseMessage = 'reason';
  static const String rrn = 'rrn';
  static const String authCode = 'authCode';
  static const String maskedPan = 'maskedPan';
  static const String partialApproval = 'partialApproval';
  static const String requestedAmount = 'requestedAmount';
  static const String raw = 'raw';
  static const String failure = 'failure';
  static const String transaction = 'transaction';
  static const String url = 'url';

  /// What the terminal says the till should do next. See [EcrNextSteps].
  static const String nextStep = 'nextStep';

  /// An inquiry map: what the terminal said when asked what became of a
  /// transaction whose answer never arrived. Absent when it was not asked.
  static const String recovered = 'recovered';

  static const List<String> all = <String>[
    outcome,
    merchantReferenceId,
    amount,
    responseCode,
    responseMessage,
    rrn,
    authCode,
    maskedPan,
    partialApproval,
    requestedAmount,
    raw,
    failure,
    transaction,
    url,
    nextStep,
    recovered,
  ];
}

/// Values of [EcrResultKeys.nextStep].
///
/// The protocol's own spelling, which is also the Kotlin and Swift enum name —
/// one word for one meaning across the terminal, both native SDKs and this
/// channel, rather than a fourth translation to keep in step.
abstract final class EcrNextSteps {
  static const String none = 'NONE';
  static const String inquireByMerchantReference =
      'INQUIRE_BY_MERCHANT_REFERENCE';

  static const List<String> all = <String>[none, inquireByMerchantReference];
}

/// Values of [EcrResultKeys.outcome] for a money-moving operation.
abstract final class EcrOutcomes {
  static const String approved = 'approved';
  static const String declined = 'declined';
  static const String failed = 'failed';

  /// Inquiry outcomes.
  static const String found = 'found';
  static const String notFound = 'notFound';

  /// Receipt outcomes.
  static const String ready = 'ready';
  static const String unavailable = 'unavailable';

  static const List<String> all = <String>[
    approved,
    declined,
    failed,
    found,
    notFound,
    ready,
    unavailable,
  ];
}

/// Keys inside the `failure` sub-map.
abstract final class EcrFailureKeys {
  static const String kind = 'kind';
  static const String message = 'message';

  static const List<String> all = <String>[kind, message];
}

/// Values of [EcrFailureKeys.kind].
///
/// The first five mirror the native SDKs' `Failure` hierarchy one for one. The
/// last two are added by this wrapper and have no native counterpart — see the
/// compatibility matrix.
abstract final class EcrFailureKinds {
  static const String unreachable = 'unreachable';
  static const String timeout = 'timeout';
  static const String malformed = 'malformed';
  static const String connectionLost = 'connectionLost';

  /// The answer could not be shown to have come from the terminal.
  static const String unauthenticated = 'unauthenticated';

  /// The caller cancelled. Wrapper-level.
  static const String cancelled = 'cancelled';

  /// The platform cannot do this at all — an unsupported transport, or an
  /// operation one platform's SDK does not offer. Wrapper-level.
  static const String unsupported = 'unsupported';

  static const List<String> all = <String>[
    unreachable,
    timeout,
    malformed,
    connectionLost,
    unauthenticated,
    cancelled,
    unsupported,
  ];
}

/// Keys inside the `transaction` sub-map of a found inquiry.
abstract final class EcrTransactionKeys {
  static const String transactionId = 'transactionId';
  static const String stan = 'stan';
  static const String type = 'type';
  static const String status = 'status';
  static const String amount = 'amount';
  static const String totalAmount = 'totalAmount';
  static const String currency = 'currency';
  static const String transactionTime = 'transactionTime';
  static const String maskedPan = 'maskedPan';
  static const String cardHolderName = 'cardHolderName';
  static const String rrn = 'rrn';
  static const String authCode = 'authCode';
  static const String batchId = 'batchId';
  static const String terminalId = 'terminalId';
  static const String isRefunded = 'isRefunded';
  static const String canVoid = 'canVoid';
  static const String canRefund = 'canRefund';

  static const List<String> all = <String>[
    transactionId,
    stan,
    type,
    status,
    amount,
    totalAmount,
    currency,
    transactionTime,
    maskedPan,
    cardHolderName,
    rrn,
    authCode,
    batchId,
    terminalId,
    isRefunded,
    canVoid,
    canRefund,
  ];
}

/// Codes a host uses when it raises an error instead of answering.
///
/// A host answers with a result map for anything that happened on the wire.
/// These two are for the cases where there is no wire exchange to describe.
abstract final class EcrErrorCodes {
  /// The arguments could not be used — a refund with no receipt number, an
  /// amount that is not a decimal. Nothing was sent, so nothing has to be
  /// reconciled; the Dart side rethrows this as [EcrArgumentError].
  static const String invalidArgument = 'ecr_invalid_argument';

  /// The host broke in a way it has no result for. The Dart side reports it as
  /// a failed result with an unknown outcome, never as a decline.
  static const String internal = 'ecr_internal';

  static const List<String> all = <String>[invalidArgument, internal];
}

/// The channel the plugin talks over.
const String kEcrMethodChannel = 'com.amwalpay.ecr/methods';
