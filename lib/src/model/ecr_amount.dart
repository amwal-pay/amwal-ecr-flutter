import 'ecr_errors.dart';

/// An amount of money, held exactly.
///
/// Amounts are never `double` anywhere in this package. A binary float cannot
/// represent 1.234, and an amount that is off by a thousandth of a rial is a
/// wrong charge that reconciles against nothing. The value is kept as the
/// digits the caller gave, and converted to the wire's minor units only at the
/// point it is sent.
///
/// ```dart
/// EcrAmount.parse('1.234');                       // 1.234
/// EcrAmount.fromMinorUnits(1234, minorUnitDigits: 3); // 1.234
/// ```
final class EcrAmount implements Comparable<EcrAmount> {
  const EcrAmount._(this._digits, this._scale);

  /// Unscaled digits, e.g. `1234` for both `1.234` (scale 3) and `12.34`
  /// (scale 2). A [BigInt] so that a large amount cannot silently wrap.
  final BigInt _digits;

  /// Decimal places [_digits] is written with.
  final int _scale;

  /// Parses a plain decimal string such as `'1.234'`, `'0'` or `'961.100'`.
  ///
  /// Rejects anything a terminal would not accept: a negative amount,
  /// exponent notation, grouping separators, or an empty string. Trailing
  /// zeros are significant and are kept, because `1.200` and `1.2` are the
  /// same amount but not the same thing to a cashier reading a receipt.
  ///
  /// Throws [EcrArgumentError] when the text is not a plain decimal.
  factory EcrAmount.parse(String text) {
    final EcrAmount? parsed = tryParse(text);
    if (parsed == null) {
      throw EcrArgumentError(
        '"$text" is not a plain decimal amount. '
        'Expected digits with an optional decimal point, e.g. "1.234".',
      );
    }
    return parsed;
  }

  /// Parses [text], answering `null` rather than throwing.
  ///
  /// The form a text field wants: an operator halfway through typing has not
  /// made a mistake, they have simply not finished.
  static EcrAmount? tryParse(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (!_plainDecimal.hasMatch(trimmed)) return null;

    final int point = trimmed.indexOf('.');
    final String whole = point < 0 ? trimmed : trimmed.substring(0, point);
    final String fraction = point < 0 ? '' : trimmed.substring(point + 1);

    final BigInt? digits = BigInt.tryParse('$whole$fraction');
    if (digits == null) return null;
    return EcrAmount._(digits, fraction.length);
  }

  /// Builds an amount from a whole number of the currency's smallest unit —
  /// 1234 baisa is 1.234 OMR at [minorUnitDigits] 3.
  factory EcrAmount.fromMinorUnits(int minorUnits, {required int minorUnitDigits}) {
    _checkDigits(minorUnitDigits);
    if (minorUnits < 0) {
      throw const EcrArgumentError('An amount cannot be negative');
    }
    return EcrAmount._(BigInt.from(minorUnits), minorUnitDigits);
  }

  /// Zero, written to [minorUnitDigits] decimal places.
  factory EcrAmount.zero({int minorUnitDigits = 3}) {
    _checkDigits(minorUnitDigits);
    return EcrAmount._(BigInt.zero, minorUnitDigits);
  }

  static final RegExp _plainDecimal = RegExp(r'^\d+(\.\d+)?$');

  static void _checkDigits(int digits) {
    if (digits < 0 || digits > 4) {
      throw EcrArgumentError('minorUnitDigits must be between 0 and 4, got $digits');
    }
  }

  /// Whether this is zero, whatever scale it was written at.
  bool get isZero => _digits == BigInt.zero;

  /// The amount as a whole number of minor units at [minorUnitDigits].
  ///
  /// Rounds half up when the amount carries more decimal places than the
  /// currency has — the same rule the Kotlin SDK's `minorUnits` applies, so a
  /// figure written 1.2345 becomes 1235 baisa on either platform rather than
  /// on one.
  BigInt toMinorUnits(int minorUnitDigits) {
    _checkDigits(minorUnitDigits);
    if (minorUnitDigits >= _scale) {
      return _digits * BigInt.from(10).pow(minorUnitDigits - _scale);
    }
    final BigInt divisor = BigInt.from(10).pow(_scale - minorUnitDigits);
    final BigInt quotient = _digits ~/ divisor;
    final BigInt remainder = _digits.remainder(divisor);
    // Half up: 5 in the first dropped place rounds away from zero.
    return remainder * BigInt.two >= divisor ? quotient + BigInt.one : quotient;
  }

  /// The amount written the way the channel carries it: a plain decimal string
  /// in major units.
  String toWireString() => toString();

  @override
  String toString() {
    if (_scale == 0) return _digits.toString();
    final String padded = _digits.toString().padLeft(_scale + 1, '0');
    final int split = padded.length - _scale;
    return '${padded.substring(0, split)}.${padded.substring(split)}';
  }

  /// Compares by value, so `1.2` and `1.200` are equal.
  @override
  int compareTo(EcrAmount other) {
    final int scale = _scale > other._scale ? _scale : other._scale;
    final BigInt ten = BigInt.from(10);
    return (_digits * ten.pow(scale - _scale))
        .compareTo(other._digits * ten.pow(scale - other._scale));
  }

  /// Equal by value, not by how it was written: `1.2 == 1.200`.
  @override
  bool operator ==(Object other) => other is EcrAmount && compareTo(other) == 0;

  @override
  int get hashCode {
    // Normalise away trailing zeros so equal amounts hash alike.
    BigInt digits = _digits;
    final BigInt ten = BigInt.from(10);
    int scale = _scale;
    while (scale > 0 && digits != BigInt.zero && digits.remainder(ten) == BigInt.zero) {
      digits = digits ~/ ten;
      scale--;
    }
    if (digits == BigInt.zero) scale = 0;
    return Object.hash(digits, scale);
  }
}
