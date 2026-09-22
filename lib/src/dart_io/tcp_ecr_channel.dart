import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../model/ecr_failure.dart';
import 'ecr_frames.dart';

/// Terminal did not answer in time. The transaction may still have run.
final class EcrChannelTimeout implements Exception {
  /// [message] explains the timeout.
  const EcrChannelTimeout(this.message);

  /// Operator-facing account of the timeout.
  final String message;

  @override
  String toString() => 'EcrChannelTimeout: $message';
}

/// One TCP connection: connect, send one framed body, read one framed answer.
final class TcpEcrChannel {
  /// [host]/[port] address the terminal; [connectTimeout] bounds the handshake.
  TcpEcrChannel({
    required this.host,
    required this.port,
    required this.connectTimeout,
  });

  /// Terminal address.
  final String host;

  /// Terminal ECR port.
  final int port;

  /// How long the connect handshake may take.
  final Duration connectTimeout;

  /// What to show an operator when this link fails.
  String get endpoint => '$host:$port';

  Socket? _socket;

  /// Closes any open socket so a cancel can interrupt a blocked read.
  void abort() {
    final Socket? socket = _socket;
    _socket = null;
    socket?.destroy();
  }

  /// Whether the terminal accepts a TCP connection within [timeout].
  ///
  /// Returns null when reachable, otherwise the failure reason.
  Future<String?> probe(Duration timeout) async {
    try {
      final Socket socket = await Socket.connect(
        host,
        port,
        timeout: timeout,
      );
      await socket.close();
      return null;
    } on SocketException catch (error) {
      return error.message;
    } on TimeoutException catch (error) {
      return error.message ?? 'Connection timed out';
    } on Object catch (error) {
      return error.toString();
    }
  }

  /// Sends [body] framed and returns the answer body.
  ///
  /// Throws [EcrChannelTimeout] on a read/connect timeout.
  Future<Uint8List> exchange(List<int> body, Duration responseTimeout) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: connectTimeout,
      );
      _socket = socket;
      socket.setOption(SocketOption.tcpNoDelay, true);

      final Uint8List packet = EcrFrames.wrap(body);
      socket.add(packet);
      await socket.flush();

      return await EcrFrames.readBody(socket).timeout(
        responseTimeout,
        onTimeout: () {
          throw const EcrChannelTimeout(
            'the terminal did not answer in time',
          );
        },
      );
    } on EcrChannelTimeout {
      rethrow;
    } on TimeoutException catch (error) {
      throw EcrChannelTimeout(
        error.message ?? 'the terminal did not answer in time',
      );
    } on SocketException catch (error) {
      if (_isTimeout(error)) {
        throw EcrChannelTimeout(
          error.message.isEmpty
              ? 'the terminal did not answer in time'
              : error.message,
        );
      }
      rethrow;
    } finally {
      final Socket? open = socket ?? _socket;
      _socket = null;
      try {
        await open?.close();
      } catch (_) {
        open?.destroy();
      }
    }
  }

  static bool _isTimeout(SocketException error) {
    final String text = error.message.toLowerCase();
    return text.contains('timed out') || text.contains('timeout');
  }
}

/// Maps a link exception into an [EcrFailure].
EcrFailure failureFromLinkError(Object error, String endpoint) {
  if (error is EcrChannelTimeout) {
    return const EcrTimeout(
      'The terminal did not answer within the configured response timeout. '
      'The transaction may still have completed — inquire before retrying.',
    );
  }
  if (error is EcrFrameException) {
    final String reason = error.message;
    if (reason.contains('not valid JSON') ||
        reason.contains('empty message')) {
      return EcrMalformed(reason);
    }
    if (reason.contains('closed the connection')) {
      return EcrConnectionLost(reason);
    }
    return EcrMalformed(reason);
  }
  if (error is FormatException) {
    return EcrMalformed(error.message);
  }
  if (error is SocketException) {
    final String reason =
        error.message.isEmpty ? error.osError?.message ?? 'Socket error' : error.message;
    if (reason.toLowerCase().contains('closed')) {
      return EcrConnectionLost(reason);
    }
    return EcrUnreachable('$reason ($endpoint)');
  }
  final String reason = error.toString();
  if (reason.contains('not valid JSON') || reason.contains('empty message')) {
    return EcrMalformed(reason);
  }
  if (reason.contains('closed the connection')) {
    return EcrConnectionLost(reason);
  }
  return EcrUnreachable('$reason ($endpoint)');
}

/// Decodes a UTF-8 JSON object from [body].
Map<String, Object?> parseJsonObject(List<int> body) {
  final String payload = utf8.decode(body);
  try {
    final Object? decoded = jsonDecode(payload);
    if (decoded is! Map) {
      throw FormatException(
        'Terminal returned a message that is not valid JSON: $payload',
      );
    }
    return decoded.map(
      (Object? key, Object? value) =>
          MapEntry<String, Object?>(key.toString(), value),
    );
  } on FormatException {
    rethrow;
  } catch (error) {
    throw FormatException(
      'Terminal returned a message that is not valid JSON: $payload',
      error,
    );
  }
}
