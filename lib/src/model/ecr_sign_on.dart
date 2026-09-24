import 'ecr_failure.dart';
import 'ecr_transaction_type.dart';
import 'ecr_transport.dart';

/// What the terminal says it is and what it will accept.
///
/// A till has no other way to know. TMS can disable an operation or move an
/// amount limit at any moment, and the terminal picks that up on its next
/// heartbeat while the till carries on offering a button that will now be
/// refused.
///
/// The answer is a snapshot, not a subscription: the socket closes after it,
/// so there is no route back to tell the till later. What keeps a stale
/// snapshot harmless is that the terminal checks its own profile again on
/// every request, and a refusal carries the current snapshot with it — see
/// `EcrDeclined.capabilities`. A till that never signs on twice still
/// corrects itself.
///
/// Reads only: no card is presented and no money moves, so it is safe to
/// repeat as often as you like.
sealed class EcrSignOn {
  /// Every outcome names the reference it was sent with.
  const EcrSignOn({required this.merchantReference});

  /// The reference this request was sent with, so a caller can match the
  /// answer to what it asked. See `EcrResult.merchantReference`.
  final String merchantReference;
}

/// The terminal answered and is in service.
final class EcrSignOnAvailable extends EcrSignOn {
  /// Carries what the terminal reported about itself.
  const EcrSignOnAvailable({
    required super.merchantReference,
    required this.capabilities,
    required this.raw,
  });

  /// What the terminal is and what it permits.
  final EcrTerminalCapabilities capabilities;

  /// The terminal's full answer as JSON text.
  final String raw;

  @override
  String toString() => 'EcrSignOnAvailable($capabilities)';
}

/// The terminal answered and cannot serve a transaction: not on its idle
/// screen, or not in ECR mode at all.
///
/// **An answer, not a failure.** "It is there and busy" and "nothing answered"
/// call for different things from a till, and reporting the first as the
/// second sends an operator to look at a network that is working perfectly.
final class EcrSignOnUnavailable extends EcrSignOn {
  /// Carries the terminal's own words about why.
  const EcrSignOnUnavailable({
    required super.merchantReference,
    required this.reason,
    required this.capabilities,
    required this.raw,
  });

  /// The terminal's own words. Worth showing: it distinguishes "sign in on the
  /// terminal" from "the terminal is mid-transaction".
  final String reason;

  /// Whatever the terminal could still report about itself. Often mostly
  /// empty — a terminal with no profile yet has little to say.
  final EcrTerminalCapabilities capabilities;

  /// The terminal's full answer as JSON text.
  final String raw;

  @override
  String toString() => 'EcrSignOnUnavailable($reason)';
}

/// The exchange itself failed. Safe to retry: nothing was changed.
final class EcrSignOnFailed extends EcrSignOn {
  /// Carries why the terminal could not be asked.
  const EcrSignOnFailed({
    required super.merchantReference,
    required this.failure,
  });

  /// Why there was no answer. Safe to retry whatever it says.
  final EcrFailure failure;

  @override
  String toString() => 'EcrSignOnFailed($failure)';
}

/// A terminal's configuration, as it reports it.
class EcrTerminalCapabilities {
  /// Every field defaults to the emptiest honest value: a terminal that said
  /// nothing is not a terminal that permits everything.
  const EcrTerminalCapabilities({
    this.available = false,
    this.reason = '',
    this.transport,
    this.ecrMode,
    this.terminalName = '',
    this.currencyCode = '',
    this.minorUnitDigits = 0,
    this.eReceipt = false,
    this.physicalReceipt = false,
    this.permitted = const <EcrPermittedTransaction>[],
  });

  /// Whether the terminal can take a transaction right now.
  final bool available;

  /// Why not, when it cannot.
  final String reason;

  /// The transport its profile puts it on, where this package knows the value.
  ///
  /// Null for an `ecrMode` this version has never heard of — which is not an
  /// error: TMS can ship a mode before a till is updated for it, and
  /// [ecrMode] still carries the number.
  final EcrTransport? transport;

  /// The raw `ecrMode` from the profile, whether or not [transport] knows it.
  final int? ecrMode;

  /// The terminal's own name from its profile, where it has one.
  final String terminalName;

  /// ISO 4217 numeric. `512` is OMR.
  final String currencyCode;

  /// Where the decimal point falls. 3 for OMR, 2 for USD, 0 for JPY.
  final int minorUnitDigits;

  /// Whether the terminal can publish an e-receipt.
  final bool eReceipt;

  /// Whether the terminal prints.
  final bool physicalReceipt;

  /// One entry per operation this till may send.
  final List<EcrPermittedTransaction> permitted;

  /// Whether [type] may be sent to this terminal at all.
  bool permits(EcrTransactionType type) =>
      permitted.any((EcrPermittedTransaction entry) => entry.type == type);

  /// What [type] allows, or null when it may not be sent.
  EcrPermittedTransaction? limitsFor(EcrTransactionType type) {
    for (final EcrPermittedTransaction entry in permitted) {
      if (entry.type == type) return entry;
    }
    return null;
  }

  @override
  String toString() =>
      'EcrTerminalCapabilities(available: $available, '
      'ecrMode: $ecrMode, permits: ${permitted.length})';
}

/// One operation a till may send, and the amounts it may send with it.
class EcrPermittedTransaction {
  /// [minAmount] and [maxAmount] are major units, as every answer reports an
  /// amount. Empty where the terminal set no limit.
  const EcrPermittedTransaction({
    required this.type,
    this.minAmount = '',
    this.maxAmount = '',
  });

  /// The operation this entry permits.
  final EcrTransactionType type;

  /// Major units, as a string, exactly as the terminal reported it. Empty when
  /// unset.
  final String minAmount;

  /// Major units, as a string. Empty when unset.
  final String maxAmount;

  @override
  String toString() =>
      'EcrPermittedTransaction(${type.messageType}, $minAmount..$maxAmount)';
}
