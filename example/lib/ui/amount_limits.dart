import 'package:amwal_ecr/amwal_ecr.dart';

/// Amount bounds, mirroring the POS purchase form.
///
/// On POS the maximum comes from the server as the terminal's transaction
/// limit, in minor units. The ECR example has no such permission call, so it is
/// a constant here — change [max] to match the limit configured for your
/// terminals.
///
/// Mirrors `AmountLimits.kt`.
abstract final class AmountLimits {
  /// POS: `minAmount = 10 / 1000`.
  static final EcrAmount min = EcrAmount.parse('0.010');

  /// POS: `amountLimit = amountlimit / 1000`.
  static final EcrAmount max = EcrAmount.parse('100000.000');

  /// Decimal places the currency has. Matches the amount field's entry.
  static const int fractionDigits = 3;

  /// Digits the field accepts, the equivalent of the POS form's `maxLength`:
  /// enough to key the maximum and no more.
  static int get maxDigits => max.toMinorUnits(fractionDigits).toString().length;

  /// Renders keyed digits as an amount: `1234` reads as `1.234`.
  ///
  /// The operator keys digits and the field shows where the point falls, which
  /// is how the POS purchase form behaves — there is no decimal key to press
  /// and no way to end up with two of them.
  static String formatDigits(String digits) {
    final String trimmed = digits.replaceAll(RegExp(r'\D'), '');
    final String padded = trimmed.padLeft(fractionDigits + 1, '0');
    final int split = padded.length - fractionDigits;
    final String whole =
        padded.substring(0, split).replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return '$whole.${padded.substring(split)}';
  }

  /// The keyed digits as an amount.
  static EcrAmount amountOf(String digits) =>
      EcrAmount.parse(formatDigits(digits));
}
