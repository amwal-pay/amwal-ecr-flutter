import 'dart:convert';

import '../model/ecr_amount.dart';
import '../model/ecr_config.dart';
import '../model/ecr_failure.dart';
import '../model/ecr_inquiry.dart';
import '../model/ecr_receipt.dart';
import '../model/ecr_result.dart';
import '../model/ecr_transaction_type.dart';
import 'ecr_message.dart';
import 'ecr_response_envelope.dart';
import 'ecr_wire_readers.dart';
import 'secure_hash.dart';
import 'tcp_ecr_channel.dart';

/// LAN / Wi‑Fi ECR client — one framed TCP exchange per call.
///
/// Mirrors Kotlin / Swift `EcrTerminal` behaviour for signing, verification,
/// and auto-inquire-on-failure.
final class LanEcrClient {
  /// Addresses the terminal at [host] with [serialNumber] and [config].
  LanEcrClient({
    required this.host,
    required this.serialNumber,
    required this.config,
  }) : _channel = TcpEcrChannel(
          host: host,
          port: config.port,
          connectTimeout: config.connectTimeout,
        );

  /// Terminal IP / hostname.
  final String host;

  /// Terminal serial as registered by the operator.
  final String serialNumber;

  /// Till identity and timeouts.
  final EcrConfig config;

  final TcpEcrChannel _channel;

  /// Aborts any in-flight TCP exchange.
  void abort() => _channel.abort();

  /// Probes whether the terminal accepts a connection.
  Future<({bool reachable, String? error})> probe() async {
    final String? problem = await _channel.probe(config.probeTimeout);
    return (reachable: problem == null, error: problem);
  }

  /// Runs a money-moving operation.
  Future<EcrResult> run({
    required EcrTransactionType type,
    EcrAmount? amount,
    String originalStan = '',
    String originalTerminalId = '',
    String originalDate = '',
    String merchantReference = '',
  }) async {
    final EcrMessage message = EcrMessage.build(
      type: type,
      config: config,
      terminalSerial: serialNumber,
      amount: amount,
      originalStan: originalStan,
      originalTerminalId: originalTerminalId,
      originalDate: originalDate,
      merchantReference: merchantReference,
    );

    final _Answer answer = await _exchange(message);
    return switch (answer) {
      _Broken(:final EcrFailure failure) =>
        await _lost(message.merchantReference, failure),
      _Ok(:final Map<String, Object?> json) => EcrWireReaders.toEcrResult(
          json,
          merchantReference: message.merchantReference,
          minorUnitDigits: config.minorUnitDigits,
        ),
    };
  }

  /// Inquiry by receipt number.
  Future<EcrInquiry> inquire({
    required String receiptNumber,
    required String transactionDate,
    String originalTerminalId = '',
    String merchantReference = '',
  }) async {
    final EcrMessage message = EcrMessage.build(
      type: EcrTransactionType.inquiry,
      config: config,
      terminalSerial: serialNumber,
      originalStan: receiptNumber,
      originalTerminalId: originalTerminalId,
      originalDate: transactionDate,
      merchantReference: merchantReference,
    );

    final _Answer answer = await _exchange(message);
    return switch (answer) {
      _Broken(:final EcrFailure failure) => EcrInquiryFailed(
          merchantReference: message.merchantReference,
          failure: failure,
        ),
      _Ok(:final Map<String, Object?> json) => EcrWireReaders.toInquiry(
          json,
          merchantReference: message.merchantReference,
          minorUnitDigits: config.minorUnitDigits,
        ),
    };
  }

  /// Inquiry by the original merchant reference.
  Future<EcrInquiry> inquireByReference({
    required String originalReference,
    String transactionDate = '',
    String originalTerminalId = '',
    String merchantReference = '',
  }) async {
    final EcrMessage message = EcrMessage.build(
      type: EcrTransactionType.inquiry,
      config: config,
      terminalSerial: serialNumber,
      originalTerminalId: originalTerminalId,
      originalDate: transactionDate,
      originalReference: originalReference,
      merchantReference: merchantReference,
    );

    final _Answer answer = await _exchange(message);
    return switch (answer) {
      _Broken(:final EcrFailure failure) => EcrInquiryFailed(
          merchantReference: message.merchantReference,
          failure: failure,
        ),
      _Ok(:final Map<String, Object?> json) => EcrWireReaders.toInquiry(
          json,
          merchantReference: message.merchantReference,
          minorUnitDigits: config.minorUnitDigits,
        ),
    };
  }

  /// Fetches an e-receipt URL.
  Future<EcrReceipt> receipt({
    required String receiptNumber,
    required String transactionDate,
    String originalTerminalId = '',
    String merchantReference = '',
  }) async {
    final EcrMessage message = EcrMessage.build(
      type: EcrTransactionType.receipt,
      config: config,
      terminalSerial: serialNumber,
      originalStan: receiptNumber,
      originalTerminalId: originalTerminalId,
      originalDate: transactionDate,
      merchantReference: merchantReference,
    );

    final _Answer answer = await _exchange(message);
    return switch (answer) {
      _Broken(:final EcrFailure failure) => EcrReceiptFailed(
          merchantReference: message.merchantReference,
          failure: failure,
        ),
      _Ok(:final Map<String, Object?> json) => EcrWireReaders.toReceipt(
          json,
          merchantReference: message.merchantReference,
        ),
    };
  }

  Future<EcrResult> _lost(String reference, EcrFailure failure) async {
    final EcrFailed plain = EcrFailed(
      merchantReference: reference,
      failure: failure,
    );
    if (!config.autoInquireOnFailure) return plain;
    if (!failure.outcomeIsUnknown) return plain;
    if (reference.isEmpty) return plain;

    EcrInquiry? found;
    try {
      found = await inquireByReference(originalReference: reference);
    } catch (_) {
      found = null;
    }
    return EcrFailed(
      merchantReference: reference,
      failure: failure,
      recovered: found,
    );
  }

  Future<_Answer> _exchange(EcrMessage message) async {
    final List<int> body = utf8.encode(jsonEncode(message.json));
    try {
      final List<int> reply =
          await _channel.exchange(body, config.responseTimeout);
      final Map<String, Object?> answer = parseJsonObject(reply);
      final EcrFailure? rejection = _untrustworthy(answer, message);
      if (rejection != null) return _Broken(rejection);
      return _Ok(answer);
    } on Object catch (error) {
      return _Broken(failureFromLinkError(error, _channel.endpoint));
    }
  }

  EcrFailure? _untrustworthy(Map<String, Object?> answer, EcrMessage sent) {
    if (!config.signsMessages) return null;

    final bool verified = SecureHash.verify(answer, config.secureHashKey);
    if (!verified) {
      return const EcrUnauthenticated(
        "The answer was not signed with this terminal's key.",
      );
    }

    final String echoed = wireString(answer['nonce']);
    if (echoed != sent.nonce) {
      return const EcrUnauthenticated(
        'The answer belongs to a different request. The transaction '
        'may still have completed — inquire before retrying.',
      );
    }
    return null;
  }
}

sealed class _Answer {
  const _Answer();
}

final class _Ok extends _Answer {
  const _Ok(this.json);
  final Map<String, Object?> json;
}

final class _Broken extends _Answer {
  const _Broken(this.failure);
  final EcrFailure failure;
}
