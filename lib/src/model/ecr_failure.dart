/// Why an exchange could not be completed.
///
/// The first five mirror the native SDKs' `Failure` hierarchy one for one.
/// [EcrCancelled] and [EcrUnsupported] are added by this wrapper — see
/// `doc/compatibility-matrix.md`.
///
/// [outcomeIsUnknown] is the field that matters. A failure where it is `true`
/// says only that *this SDK* learned nothing; the terminal may have taken the
/// money and been unable to say so. Retrying such a request is how a customer
/// gets charged twice. Send an inquiry for the same receipt number instead.
sealed class EcrFailure {
  /// Describes the failure in a sentence an operator could be shown.
  const EcrFailure(this.message);

  /// A human-readable account of the failure.
  final String message;

  /// Whether the transaction may nonetheless have completed.
  ///
  /// `true` means: do not retry, reconcile. `false` means nothing was sent or
  /// the terminal refused before anything moved, so a retry is safe.
  bool get outcomeIsUnknown;

  @override
  String toString() => '$runtimeType($message)';
}

/// Nothing is listening: wrong address, terminal off, or a different network.
final class EcrUnreachable extends EcrFailure {
  /// [message] names the address that did not answer.
  const EcrUnreachable(super.message);

  /// Nothing was sent, so nothing happened.
  @override
  bool get outcomeIsUnknown => false;
}

/// The terminal accepted the request but never answered.
///
/// **Not a decline.** The card flow does not depend on the socket staying up,
/// so the payment may have gone through.
final class EcrTimeout extends EcrFailure {
  /// [message] says how long was waited, and that the outcome is unknown.
  const EcrTimeout(super.message);

  @override
  bool get outcomeIsUnknown => true;
}

/// The terminal answered with something this SDK could not read.
///
/// The terminal did answer, so it acted on the request; what it did is not
/// legible from here.
final class EcrMalformed extends EcrFailure {
  /// [message] carries what arrived, so it can be compared to the protocol.
  const EcrMalformed(super.message);

  @override
  bool get outcomeIsUnknown => true;
}

/// The connection broke part way through.
final class EcrConnectionLost extends EcrFailure {
  /// [message] says at which point the connection went.
  const EcrConnectionLost(super.message);

  @override
  bool get outcomeIsUnknown => true;
}

/// The answer could not be shown to have come from the terminal.
///
/// Either it was not signed with this till's key, or it answered a different
/// request. Both mean something else may have replied on the terminal's port —
/// so the answer is discarded rather than believed.
///
/// **Not a decline.** The terminal may have taken the payment; it simply cannot
/// be confirmed from here. Inquire before retrying, and never treat it as a
/// refusal. Seeing this repeatedly usually means the key on this till and the
/// key on the terminal do not match.
final class EcrUnauthenticated extends EcrFailure {
  /// [message] says which of the two checks the answer failed.
  const EcrUnauthenticated(super.message);

  @override
  bool get outcomeIsUnknown => true;
}

/// The caller cancelled while the request was in flight.
///
/// Wrapper-level: the native SDKs have no such case. Cancelling closes the
/// socket, which tells the terminal nothing — a cardholder mid-PIN carries on,
/// and the payment may complete. Treat it exactly like [EcrTimeout].
///
/// Cancelling before the request is sent cannot happen: the operation is
/// registered and dispatched in the same step.
final class EcrCancelled extends EcrFailure {
  /// The default [message] is the warning that matters; override it only to
  /// say something the caller knows and this package does not.
  const EcrCancelled([
    super.message = 'The caller cancelled while the terminal had the request. '
        'The transaction may still have completed — inquire before retrying.',
  ]);

  @override
  bool get outcomeIsUnknown => true;
}

/// The platform cannot perform this at all.
///
/// Wrapper-level, and the answer to "what does the API do where the two
/// platforms differ": an unsupported transport, or an operation one platform's
/// SDK does not offer. Raised before anything is sent.
final class EcrUnsupported extends EcrFailure {
  /// [message] says what was asked for and why this platform cannot do it.
  const EcrUnsupported(super.message);

  /// Nothing was attempted, so nothing happened.
  @override
  bool get outcomeIsUnknown => false;
}
