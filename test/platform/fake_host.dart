import 'dart:async';

import 'package:amwal_ecr/amwal_ecr_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for the native host, which records everything it is asked.
///
/// The point of it is counting. Most of what can go wrong across a channel is
/// not a wrong value but a wrong *number* of things: a request sent twice, a
/// future completed twice, a reply arriving after the caller has moved on.
/// Those are invisible to a test that only inspects the last answer, so this
/// keeps the whole log.
final class FakeEcrHost {
  FakeEcrHost() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, _handle);
  }

  /// The channel the plugin really uses, so the test exercises the real name.
  static const MethodChannel channel = MethodChannel(kEcrMethodChannel);

  /// Every call the host received, in order. Never cleared by the host itself.
  final List<MethodCall> calls = <MethodCall>[];

  /// What to answer, by method name. A handler may take as long as it likes.
  final Map<String, Future<Object?> Function(MethodCall call)> answers =
      <String, Future<Object?> Function(MethodCall call)>{};

  /// Replies that are being held open, keyed by method name.
  final Map<String, Completer<Object?>> _held = <String, Completer<Object?>>{};

  /// Method names invoked, in order — the readable form of [calls].
  List<String> get methods =>
      calls.map((MethodCall call) => call.method).toList();

  /// How many times [method] was invoked. The retry detector.
  int countOf(String method) =>
      calls.where((MethodCall call) => call.method == method).length;

  /// The arguments of the first [method] call.
  Map<Object?, Object?> argumentsOf(String method) => calls
      .firstWhere((MethodCall call) => call.method == method)
      .arguments as Map<Object?, Object?>;

  /// The value of [key] in every recorded call's arguments, in order.
  ///
  /// For the assertions that are about how values vary across calls — that two
  /// sales got two different operation ids, that each terminal sent its own
  /// transport — rather than about one call's contents.
  List<Object?> argumentValues(String key) => calls
      .map((MethodCall call) => (call.arguments as Map<Object?, Object?>)[key])
      .toList();

  /// Answers [method] with [value] as soon as it is called.
  void answer(String method, Object? value) {
    answers[method] = (MethodCall _) async => value;
  }

  /// Answers [method] by throwing [error].
  void fail(String method, Object error) {
    answers[method] = (MethodCall _) async => throw error;
  }

  /// Holds [method] open until [release] is called, so a test can do something
  /// — cancel, usually — while the terminal still has the request.
  void hold(String method) {
    final Completer<Object?> gate = Completer<Object?>();
    _held[method] = gate;
    answers[method] = (MethodCall _) => gate.future;
  }

  /// Lets a held [method] answer at last.
  void release(String method, Object? value) {
    final Completer<Object?>? gate = _held.remove(method);
    if (gate == null || gate.isCompleted) return;
    gate.complete(value);
  }

  /// Whether a held reply is still outstanding.
  bool isHolding(String method) => _held.containsKey(method);

  Future<Object?> _handle(MethodCall call) {
    calls.add(call);
    final Future<Object?> Function(MethodCall call)? answer =
        answers[call.method];
    if (answer == null) {
      return Future<Object?>.error(
        MissingPluginException('No answer registered for ${call.method}'),
      );
    }
    return answer(call);
  }

  /// Unhooks the channel. Call from tearDown.
  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    for (final Completer<Object?> gate in _held.values) {
      if (!gate.isCompleted) gate.complete(null);
    }
    _held.clear();
  }
}

/// The map an approved sale comes back as.
Map<String, Object?> approvedPayload({
  String merchantReferenceId = 'A1B2C3D4E5F6',
  String amount = '1.234',
  String responseCode = '00',
  bool partialApproval = false,
  String requestedAmount = '',
}) =>
    <String, Object?>{
      EcrResultKeys.outcome: EcrOutcomes.approved,
      EcrResultKeys.merchantReferenceId: merchantReferenceId,
      EcrResultKeys.amount: amount,
      EcrResultKeys.responseCode: responseCode,
      EcrResultKeys.rrn: '622113155340',
      EcrResultKeys.authCode: '517842',
      EcrResultKeys.maskedPan: '543173xxxx5785',
      EcrResultKeys.partialApproval: partialApproval,
      EcrResultKeys.requestedAmount: requestedAmount,
      EcrResultKeys.raw: '{"approved":true}',
    };

/// The map a decline comes back as.
Map<String, Object?> declinedPayload({
  String merchantReferenceId = 'A1B2C3D4E5F6',
  String responseCode = '51',
  String reason = 'Insufficient funds',
}) =>
    <String, Object?>{
      EcrResultKeys.outcome: EcrOutcomes.declined,
      EcrResultKeys.merchantReferenceId: merchantReferenceId,
      EcrResultKeys.responseCode: responseCode,
      EcrResultKeys.responseMessage: reason,
      EcrResultKeys.raw: '{"approved":false}',
    };

/// The map a failure comes back as.
Map<String, Object?> failedPayload({
  String merchantReferenceId = 'A1B2C3D4E5F6',
  String kind = EcrFailureKinds.timeout,
  String message = 'The terminal did not answer',
}) =>
    <String, Object?>{
      EcrResultKeys.outcome: EcrOutcomes.failed,
      EcrResultKeys.merchantReferenceId: merchantReferenceId,
      EcrResultKeys.failure: <String, Object?>{
        EcrFailureKeys.kind: kind,
        EcrFailureKeys.message: message,
      },
    };
