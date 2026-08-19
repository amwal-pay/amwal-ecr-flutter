/// The response codes the *terminal* generates itself, before anything reaches
/// the payment backend.
///
/// Anything not listed here is the backend's own code passed through untouched
/// — `00` approved, `51` declined, `909`, `05`. Never decide from a code alone:
/// the terminal's `approved` flag is authoritative, and a partial approval that
/// was then voided comes back carrying the bank's `00`.
abstract final class EcrResponseCode {
  /// Approved by the backend. Still not proof money moved — read `approved`.
  static const String approved = '00';

  /// Unsupported message type, or one this terminal cannot perform.
  static const String unsupportedOperation = '12';

  /// The amount is not valid.
  static const String invalidAmount = '13';

  /// Cancelled at the terminal, by the operator or the cardholder.
  static const String cancelledAtTerminal = '17';

  /// The original transaction was not found.
  static const String originalNotFound = '25';

  /// Unsigned, signed with the wrong key, or the till's clock is too far out.
  ///
  /// A configuration fault, not a payment decision — nothing was attempted, so
  /// there is nothing to reconcile. Signing is switched on per terminal by the
  /// key TMS issues, so seeing this usually means one of three things: the till
  /// is sending unsigned to a terminal that requires a signature, the two keys
  /// are not the same, or the till's clock is more than five minutes from the
  /// terminal's. The terminal's own `reason` says which.
  static const String securityViolation = '63';

  /// The transaction did not complete, or the terminal could not say.
  ///
  /// The one terminal-generated code where money may nonetheless have moved.
  static const String indeterminate = '91';

  /// The terminal has already answered this exact message — the nonce repeats.
  ///
  /// **Not a plain refusal.** It means the transaction this message names
  /// probably *exists*, so the outcome is a question rather than a decision.
  /// Inquire rather than retry — see [leavesOutcomeUnknown].
  static const String alreadyAnswered = '94';

  /// A transaction is already running on this terminal.
  ///
  /// Never returned for an inquiry or a receipt: reading changes nothing, so
  /// the terminal answers those while busy.
  static const String terminalBusy = '96';

  /// Whether [code] is one the terminal generated rather than the backend.
  static bool isTerminalGenerated(String code) => const <String>{
        unsupportedOperation,
        invalidAmount,
        cancelledAtTerminal,
        originalNotFound,
        securityViolation,
        indeterminate,
        alreadyAnswered,
        terminalBusy,
      }.contains(code);

  /// Whether a decline carrying [code] leaves the financial outcome unknown.
  ///
  /// [indeterminate] and [alreadyAnswered] do. The first is the terminal saying
  /// outright that it cannot tell; the second is the terminal saying it has
  /// answered this message before, which means the transaction it names
  /// probably exists — a repeat is not proof that nothing happened, it is
  /// evidence that something did.
  ///
  /// Every other terminal-generated refusal happened before anything reached
  /// the backend, and a backend decline is a decision, not a gap.
  static bool leavesOutcomeUnknown(String code) =>
      code == indeterminate || code == alreadyAnswered;
}
