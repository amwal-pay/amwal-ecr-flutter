/// Thrown when a caller asks for something the API cannot express.
///
/// Kept apart from a transaction outcome on purpose: this is a mistake in the
/// calling code — a refund with no receipt number, an amount that is not a
/// number — and is discovered before anything reaches the terminal. Nothing was
/// sent, so nothing has to be reconciled.
///
/// A failure that happens once a request *is* on its way is never thrown; it
/// comes back as an `EcrFailed` result, because by then the outcome may be
/// unknown and an exception is the wrong shape for that.
///
/// Implements [ArgumentError] rather than extending it so that it can be
/// `const`: these are raised from argument checks on paths that should cost
/// nothing, and existing `catch (ArgumentError)` handlers still see it.
final class EcrArgumentError implements ArgumentError {
  /// Describes what the caller asked for and why it cannot be done.
  const EcrArgumentError(this.message);

  /// What was wrong, in a sentence a developer can act on.
  @override
  final Object? message;

  /// Always null: the value is described in [message], which reads better than
  /// a bare figure with no account of what was expected.
  @override
  Object? get invalidValue => null;

  /// Always null. See [invalidValue].
  @override
  String? get name => null;

  /// Always null: these are thrown before anything asynchronous starts, so the
  /// throw site is the whole of the story.
  @override
  StackTrace? get stackTrace => null;

  @override
  String toString() => 'EcrArgumentError: $message';
}
