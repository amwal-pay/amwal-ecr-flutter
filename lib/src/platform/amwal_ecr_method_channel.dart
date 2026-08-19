import 'dart:async';

import 'package:flutter/services.dart';

import '../model/ecr_errors.dart';
import '../model/ecr_failure.dart';
import '../model/ecr_inquiry.dart';
import '../model/ecr_receipt.dart';
import '../model/ecr_result.dart';
import 'amwal_ecr_platform.dart';
import 'ecr_channel_contract.dart';
import 'ecr_codec.dart';
import 'ecr_request.dart';

/// Drives the terminal through the native ECR SDK on the other side of a
/// [MethodChannel].
///
/// The whole of this class is about one guarantee: **one call, one answer.**
/// A money-moving request is sent exactly once and its future completes exactly
/// once, whatever the host does afterwards. Nothing here retries, and nothing
/// here can complete a future a second time — a late reply arriving after a
/// cancel is dropped, because by then the caller has already been told the
/// outcome is unknown and has acted on it.
base class MethodChannelAmwalEcr extends AmwalEcrPlatform {
  /// [channel] is for tests, which pass one carrying a mock handler. Leave it
  /// unset in production so the plugin binds to [kEcrMethodChannel].
  MethodChannelAmwalEcr({MethodChannel? channel})
      : channel = channel ?? const MethodChannel(kEcrMethodChannel);

  /// Visible for tests, which swap in a channel with a mock handler.
  final MethodChannel channel;

  /// Operations the host has been given and has not yet answered.
  ///
  /// Keyed by the client-generated operation id, which is also what [cancel]
  /// names. An entry is removed the moment its future settles, so a second
  /// completion has nothing to settle.
  /// `_Operation<Object>` rather than the call's own type: Dart's generics are
  /// covariant, so an `_Operation<EcrResult>` slots in without a cast, and
  /// nothing here settles an operation it did not create.
  final Map<String, _Operation<Object>> _inFlight = <String, _Operation<Object>>{};

  /// How many operations are still waiting on the host. For tests and for a
  /// till that wants to refuse a second transaction while one is running.
  int get inFlightCount => _inFlight.length;

  @override
  Future<bool> isReachable(EcrRequest request) async {
    // A probe cannot leave anything half-done, so it needs none of the
    // one-shot machinery — and a host that breaks answers "not reachable",
    // which is true of a host that cannot be asked.
    try {
      final bool? reachable = await channel.invokeMethod<bool>(
        EcrMethods.isReachable,
        request.toArguments(),
      );
      return reachable ?? false;
    } on PlatformException catch (error) {
      if (error.code == EcrErrorCodes.invalidArgument) {
        throw EcrArgumentError(error.message ?? 'Invalid arguments');
      }
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<EcrResult> sale(EcrRequest request) =>
      _invokeResult(EcrMethods.sale, request);

  @override
  Future<EcrResult> voidTransaction(EcrRequest request) =>
      _invokeResult(EcrMethods.voidTransaction, request);

  @override
  Future<EcrResult> refund(EcrRequest request) =>
      _invokeResult(EcrMethods.refund, request);

  @override
  Future<EcrInquiry> inquire(EcrRequest request) =>
      _invokeInquiry(EcrMethods.inquire, request);

  @override
  Future<EcrInquiry> inquireByReference(EcrRequest request) =>
      _invokeInquiry(EcrMethods.inquireByReference, request);

  Future<EcrInquiry> _invokeInquiry(String method, EcrRequest request) =>
      _invoke<EcrInquiry>(
        method: method,
        request: request,
        decode: (Object? payload) =>
            EcrCodec.inquiry(payload, operationId: request.operationId),
        onHostError: (EcrFailure failure) =>
            EcrInquiryFailed(merchantReferenceId: '', failure: failure),
      );

  @override
  Future<EcrReceipt> receipt(EcrRequest request) => _invoke<EcrReceipt>(
        method: EcrMethods.receipt,
        request: request,
        decode: (Object? payload) =>
            EcrCodec.receipt(payload, operationId: request.operationId),
        onHostError: (EcrFailure failure) =>
            EcrReceiptFailed(merchantReferenceId: '', failure: failure),
      );

  Future<EcrResult> _invokeResult(String method, EcrRequest request) =>
      _invoke<EcrResult>(
        method: method,
        request: request,
        decode: (Object? payload) =>
            EcrCodec.result(payload, operationId: request.operationId),
        onHostError: (EcrFailure failure) =>
            EcrFailed(merchantReferenceId: '', failure: failure),
      );

  @override
  Future<bool> cancel(String operationId) async {
    final _Operation<Object>? operation = _inFlight[operationId];
    if (operation == null) {
      // Already answered, or never started. Either way there is nothing to
      // interrupt, and saying so is more useful than pretending.
      return false;
    }

    operation.cancelRequested = true;

    try {
      final bool? wasRunning = await channel.invokeMethod<bool>(
        EcrMethods.cancel,
        <String, Object?>{EcrArgs.operationId: operationId},
      );
      return wasRunning ?? false;
    } on PlatformException {
      // The host could not be asked to stop. The operation's own future still
      // settles on whatever the host eventually says, or on its timeout.
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Sends one request and settles exactly once.
  Future<T> _invoke<T extends Object>({
    required String method,
    required EcrRequest request,
    required T Function(Object? payload) decode,
    required T Function(EcrFailure failure) onHostError,
  }) {
    if (_inFlight.containsKey(request.operationId)) {
      throw EcrArgumentError(
        'Operation "${request.operationId}" is already in flight. '
        'Each call needs its own operation id.',
      );
    }

    final _Operation<T> operation = _Operation<T>();
    _inFlight[request.operationId] = operation;

    // Deliberately not awaited: the reply is funnelled through settle(), which
    // is a no-op once the operation has already been answered.
    unawaited(
      channel
          .invokeMethod<Object?>(method, request.toArguments())
          .then<void>(
            (Object? payload) => operation.settle(decode(payload)),
            onError: (Object error, StackTrace stackTrace) {
              if (error is PlatformException &&
                  error.code == EcrErrorCodes.invalidArgument) {
                // The request was refused before it was sent, so nothing has to
                // be reconciled and an exception is the honest shape.
                operation.settleError(
                  EcrArgumentError(error.message ?? 'Invalid arguments'),
                  stackTrace,
                );
                return;
              }
              operation.settle(onHostError(_hostFailure(error)));
            },
          )
          .whenComplete(() => _inFlight.remove(request.operationId)),
    );

    return operation.future;
  }

  /// Turns a host-level error into a failure.
  ///
  /// Everything here is an unknown outcome by construction: the host was given
  /// a request and then stopped making sense, and there is no way from this
  /// side to know whether the terminal acted on it.
  static EcrFailure _hostFailure(Object error) {
    if (error is MissingPluginException) {
      return const EcrUnsupported(
        'The Amwal ECR plugin is not registered on this platform. '
        'A hot restart after adding the package is usually enough; a full '
        'rebuild always is.',
      );
    }
    if (error is PlatformException) {
      final String detail = error.message ?? error.code;
      return EcrMalformed(
        'The host could not complete the request ($detail). '
        'The transaction may still have happened — inquire before retrying.',
      );
    }
    return EcrMalformed(
      'The host failed unexpectedly ($error). '
      'The transaction may still have happened — inquire before retrying.',
    );
  }
}

/// One in-flight call, and the guarantee that it settles once.
final class _Operation<T extends Object> {
  final Completer<T> _completer = Completer<T>();

  /// Set when the caller has asked for a cancel. Kept for diagnosis: a reply
  /// that arrives after this was set is the "late callback" case, and is
  /// dropped rather than delivered.
  bool cancelRequested = false;

  Future<T> get future => _completer.future;

  /// Delivers [value], or does nothing if this operation already answered.
  void settle(T value) {
    if (_completer.isCompleted) return;
    _completer.complete(value);
  }

  /// Fails the operation, or does nothing if it already answered.
  void settleError(Object error, StackTrace stackTrace) {
    if (_completer.isCompleted) return;
    _completer.completeError(error, stackTrace);
  }
}
