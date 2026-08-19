import '../model/ecr_amount.dart';
import '../model/ecr_config.dart';
import '../model/ecr_transport.dart';
import 'ecr_channel_contract.dart';

/// One call's worth of arguments, on their way to the host.
///
/// Every field the channel carries is here, so the arguments a host receives
/// can be asserted against this one object rather than reconstructed from six
/// call sites.
final class EcrRequest {
  /// Built by [EcrTerminal] for each call; assembled by hand only in tests.
  const EcrRequest({
    required this.operationId,
    required this.host,
    required this.serialNumber,
    required this.transport,
    required this.config,
    this.amount,
    this.receiptNumber = '',
    this.transactionDate = '',
    this.originalTerminalId = '',
    this.merchantReferenceId = '',
    this.originalMerchantReference = '',
  });

  /// Client-generated handle, so a cancel can name this call.
  final String operationId;

  /// The terminal's address on the local network.
  final String host;

  /// The terminal's serial number, as the operator registered it.
  final String serialNumber;

  /// How the terminal is attached, from its TMS profile.
  final EcrTransport transport;

  /// How this till identifies itself and how long it waits.
  final EcrConfig config;

  /// Null for operations that carry no amount — a void takes the original's.
  ///
  /// Nullable on the channel too: the host reads its absence as "this
  /// operation has no amount", exactly as the wire protocol reads a missing
  /// field.
  final EcrAmount? amount;

  /// The original's receipt number as the operator typed it, unpadded.
  final String receiptNumber;

  /// The original's day as `yyyyMMdd`.
  final String transactionDate;

  /// Empty means "this terminal" — never null, matching the native defaults.
  final String originalTerminalId;

  /// The till's own reference for this request.
  ///
  /// Empty has the native SDK generate one, which comes back on the result — so
  /// a caller that does not number its own orders still gets a handle it can
  /// inquire by later.
  final String merchantReferenceId;

  /// The reference an *earlier* transaction was sent with, for a lookup by
  /// reference. Empty for every other call.
  final String originalMerchantReference;

  /// The argument map as it crosses the channel.
  ///
  /// Amounts go as a decimal string in major units. The host converts to minor
  /// units with [EcrConfig.minorUnitDigits], so the conversion happens once, in
  /// the same place on both platforms, using the same rounding.
  Map<String, Object?> toArguments() => <String, Object?>{
        EcrArgs.operationId: operationId,
        EcrArgs.host: host,
        EcrArgs.serialNumber: serialNumber,
        EcrArgs.transport: transport.channelName,
        EcrArgs.config: <String, Object?>{
          EcrConfigKeys.ecrId: config.ecrId,
          EcrConfigKeys.currencyCode: config.currencyCode,
          EcrConfigKeys.minorUnitDigits: config.minorUnitDigits,
          EcrConfigKeys.port: config.port,
          EcrConfigKeys.connectTimeoutMs: config.connectTimeout.inMilliseconds,
          EcrConfigKeys.responseTimeoutMs: config.responseTimeout.inMilliseconds,
          EcrConfigKeys.probeTimeoutMs: config.probeTimeout.inMilliseconds,
          EcrConfigKeys.secureHashKey: config.secureHashKey,
          EcrConfigKeys.autoInquireOnFailure: config.autoInquireOnFailure,
        },
        EcrArgs.amount: amount?.toWireString(),
        EcrArgs.receiptNumber: receiptNumber,
        EcrArgs.transactionDate: transactionDate,
        EcrArgs.originalTerminalId: originalTerminalId,
        EcrArgs.merchantReferenceId: merchantReferenceId,
        EcrArgs.originalMerchantReference: originalMerchantReference,
      };

  @override
  String toString() => 'EcrRequest(operationId: $operationId, host: $host, '
      'transport: ${transport.name})';
}
