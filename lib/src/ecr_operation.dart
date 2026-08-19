import 'dart:async';

/// A request the terminal has, and the answer when it comes.
///
/// Returned by the `start…` methods, for a till that needs to offer a Cancel
/// button while the cardholder is at the terminal. The awaiting form —
/// `terminal.sale(…)` — is the same thing with the handle thrown away.
///
/// ```dart
/// final EcrOperation<EcrResult> sale =
///     terminal.startSale(EcrAmount.parse('1.234'));
///
/// cancelButton.onPressed = sale.cancel;
///
/// final EcrResult result = await sale.result;
/// ```
final class EcrOperation<T extends Object> {
  /// Wraps an in-flight call. Built by [EcrTerminal]'s `start…` methods —
  /// there is no reason to construct one by hand outside a test.
  EcrOperation({
    required this.operationId,
    required this.result,
    required Future<bool> Function(String operationId) onCancel,
  }) : _onCancel = onCancel;

  /// The handle the host knows this call by.
  ///
  /// Not the protocol's `merchantReferenceId` — that one names the transaction
  /// to the terminal and arrives on the result. This one never leaves the
  /// device, and exists so a cancel can name a call that has not answered yet.
  final String operationId;

  /// Completes exactly once, with the outcome — including the outcome
  /// "cancelled", which is an unknown financial outcome and not a refusal.
  final Future<T> result;

  final Future<bool> Function(String operationId) _onCancel;

  bool _cancelRequested = false;

  /// Whether [cancel] has been called. The operation may still answer with a
  /// real outcome afterwards: a cancel is a request, not a guarantee.
  bool get isCancelRequested => _cancelRequested;

  /// Asks the terminal to be let go of.
  ///
  /// Answers whether anything was still running. `false` means the operation
  /// had already finished and nothing was interrupted — its real outcome is on
  /// [result].
  ///
  /// **Cancelling a money-moving request does not undo it.** Closing the socket
  /// tells the terminal nothing; a cardholder halfway through a PIN carries on,
  /// and the payment may complete. A cancelled sale leaves the outcome unknown,
  /// exactly like a timeout: inquire on the receipt number before doing
  /// anything else.
  Future<bool> cancel() {
    _cancelRequested = true;
    return _onCancel(operationId);
  }
}
