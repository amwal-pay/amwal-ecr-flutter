import 'ecr_result.dart';

/// What the till should do about an outcome it cannot act on directly.
///
/// Stated by the terminal rather than left for a till to infer from a response
/// code, because the wrong inference is expensive: reading an unknown outcome as
/// a refusal and sending the sale again charges the cardholder twice.
///
/// Read it off [EcrResult.nextStep].
enum EcrNextStep {
  /// The answer settles the matter. Nothing further is needed.
  none('NONE'),

  /// Ask what became of the transaction, quoting the reference it was sent with
  /// — `EcrTerminal.inquireByReference`.
  ///
  /// That reference is the only identifier a till holds before the terminal
  /// answers: a receipt number arrives *in* the answer, which is exactly what
  /// went missing. **Never retry instead.**
  inquireByMerchantReference('INQUIRE_BY_MERCHANT_REFERENCE');

  const EcrNextStep(this.channelName);

  /// The name this step crosses the channel under.
  ///
  /// The protocol's own spelling, which is also the Kotlin and Swift enum name —
  /// one word for one meaning across the terminal, both native SDKs and this
  /// package.
  final String channelName;

  /// Whether the till has to go and find out what happened.
  bool get needsInquiry => this == EcrNextStep.inquireByMerchantReference;

  /// Reads a channel value.
  ///
  /// Anything this version does not know reads as [none]: a till must not act on
  /// a step it does not understand, and the outcome it is attached to already
  /// says whether money may have moved.
  static EcrNextStep parse(String? value) {
    for (final EcrNextStep step in EcrNextStep.values) {
      if (step.channelName == value) return step;
    }
    return EcrNextStep.none;
  }
}
