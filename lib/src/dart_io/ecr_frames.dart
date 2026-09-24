import 'dart:async';
import 'dart:typed_data';

/// Wire framing: 2-byte big-endian length + UTF-8 JSON body.
///
/// Mirrors Kotlin `EcrFrames` / Swift `EcrFrames`.
abstract final class EcrFrames {
  /// Bytes in the length header.
  static const int headerBytes = 2;

  /// Longest body the header can describe.
  static const int maxBodyBytes = 0xFFFF;

  /// Puts a length header in front of [body].
  static Uint8List wrap(List<int> body) {
    if (body.length > maxBodyBytes) {
      throw EcrFrameException(
        'Message of ${body.length} bytes does not fit a frame',
      );
    }
    final Uint8List packet = Uint8List(headerBytes + body.length);
    packet[0] = (body.length >> 8) & 0xFF;
    packet[1] = body.length & 0xFF;
    packet.setRange(headerBytes, packet.length, body);
    return packet;
  }

  /// The body length a header announces.
  static int bodyLength(List<int> header) {
    if (header.length < headerBytes) {
      throw const EcrFrameException('Frame header is too short');
    }
    return ((header[0] & 0xFF) << 8) | (header[1] & 0xFF);
  }

  /// Reads exactly one message body from [input].
  static Future<Uint8List> readBody(Stream<List<int>> input) async {
    final _ByteAccumulator accumulator = _ByteAccumulator(input);
    final List<int> header =
        await accumulator.readExactly(headerBytes, 'response header');
    final int length = bodyLength(header);
    if (length <= 0) {
      throw const EcrFrameException('Terminal returned an empty message');
    }
    return Uint8List.fromList(
      await accumulator.readExactly(length, 'response body'),
    );
  }
}

/// Framing / stream read failure on the ECR link.
final class EcrFrameException implements Exception {
  /// Describes what went wrong while framing or reading a body.
  const EcrFrameException(this.message);

  /// Operator-facing account of the failure.
  final String message;

  @override
  String toString() => 'EcrFrameException: $message';
}

final class _ByteAccumulator {
  _ByteAccumulator(this._input);

  final Stream<List<int>> _input;
  final List<int> _buffer = <int>[];
  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _wait;
  bool _done = false;
  Object? _error;
  StackTrace? _stackTrace;

  Future<List<int>> readExactly(int count, String what) async {
    _ensureListening();
    while (_buffer.length < count) {
      if (_error != null) {
        Error.throwWithStackTrace(_error!, _stackTrace ?? StackTrace.current);
      }
      if (_done) {
        throw EcrFrameException(
          'Terminal closed the connection while sending the $what',
        );
      }
      _wait = Completer<void>();
      await _wait!.future;
    }
    final List<int> chunk = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return chunk;
  }

  void _ensureListening() {
    if (_subscription != null) return;
    _subscription = _input.listen(
      (List<int> data) {
        _buffer.addAll(data);
        _wait?.complete();
        _wait = null;
      },
      onError: (Object error, StackTrace stackTrace) {
        _error = error;
        _stackTrace = stackTrace;
        _wait?.complete();
        _wait = null;
      },
      onDone: () {
        _done = true;
        _wait?.complete();
        _wait = null;
      },
      cancelOnError: false,
    );
  }
}
