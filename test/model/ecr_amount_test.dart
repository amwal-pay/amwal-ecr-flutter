import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Amounts, which are the one thing here that must never be approximately
/// right.
///
/// The Kotlin SDK's `AmountReportingTest` is the reference for the conversions;
/// these assert the Dart side of the same contract, including the rounding rule
/// both hosts apply.
void main() {
  group('parsing', () {
    test('reads a plain decimal', () {
      expect(EcrAmount.parse('1.234').toString(), '1.234');
      expect(EcrAmount.parse('0').toString(), '0');
      expect(EcrAmount.parse('961.100').toString(), '961.100');
    });

    test('keeps trailing zeros, because 1.200 is what the cashier typed', () {
      expect(EcrAmount.parse('1.200').toString(), '1.200');
      expect(EcrAmount.parse('1.2').toString(), '1.2');
    });

    test('refuses what a terminal would refuse', () {
      for (final String bad in <String>[
        '',
        '   ',
        '-1.000',
        '1.2e3',
        '1,234',
        'abc',
        '1.',
        '.5',
        '1.2.3',
      ]) {
        expect(
          () => EcrAmount.parse(bad),
          throwsA(isA<EcrArgumentError>()),
          reason: '"$bad" should not parse',
        );
        expect(EcrAmount.tryParse(bad), isNull, reason: '"$bad" should not parse');
      }
    });

    test('tryParse is the form a half-typed text field wants', () {
      // An operator partway through typing has not made a mistake.
      expect(EcrAmount.tryParse('1.'), isNull);
      expect(EcrAmount.tryParse('1.2'), isNotNull);
    });

    test('surrounding whitespace is trimmed, not rejected', () {
      expect(EcrAmount.parse('  1.234  ').toString(), '1.234');
    });

    test('a very large amount does not wrap', () {
      // BigInt digits, so a figure past 2^63 is still exact rather than
      // silently negative.
      const String huge = '99999999999999999999.999';
      expect(EcrAmount.parse(huge).toString(), huge);
    });
  });

  group('to minor units — what goes on the wire', () {
    test('at the currency\'s own decimal places', () {
      expect(EcrAmount.parse('1.234').toMinorUnits(3).toString(), '1234');
      expect(EcrAmount.parse('0.365').toMinorUnits(3).toString(), '365');
      expect(EcrAmount.parse('961.100').toMinorUnits(3).toString(), '961100');
    });

    test('a currency with fewer places shifts the point, not the digits', () {
      expect(EcrAmount.parse('1.23').toMinorUnits(2).toString(), '123');
      expect(EcrAmount.parse('123').toMinorUnits(0).toString(), '123');
    });

    test('an amount written short is padded, not truncated', () {
      expect(EcrAmount.parse('1.2').toMinorUnits(3).toString(), '1200');
      expect(EcrAmount.parse('1').toMinorUnits(3).toString(), '1000');
    });

    test('an amount written long rounds HALF UP, as both hosts do', () {
      // The boundary. Kotlin's RoundingMode.HALF_UP and Swift's NSRoundPlain
      // agree here, and this test is what keeps Dart agreeing with them.
      expect(EcrAmount.parse('1.2345').toMinorUnits(3).toString(), '1235');
      expect(EcrAmount.parse('1.2344').toMinorUnits(3).toString(), '1234');
      expect(EcrAmount.parse('1.2346').toMinorUnits(3).toString(), '1235');
      expect(EcrAmount.parse('0.0005').toMinorUnits(3).toString(), '1');
      expect(EcrAmount.parse('0.0004').toMinorUnits(3).toString(), '0');
    });

    test('zero is zero at every scale', () {
      expect(EcrAmount.parse('0.000').toMinorUnits(3).toString(), '0');
      expect(EcrAmount.zero().toMinorUnits(3).toString(), '0');
      expect(EcrAmount.zero(minorUnitDigits: 2).toString(), '0.00');
    });

    test('an impossible number of decimal places is refused', () {
      expect(
        () => EcrAmount.parse('1.234').toMinorUnits(5),
        throwsA(isA<EcrArgumentError>()),
      );
      expect(
        () => EcrAmount.parse('1.234').toMinorUnits(-1),
        throwsA(isA<EcrArgumentError>()),
      );
    });
  });

  group('from minor units — what a terminal reports', () {
    test('1234 baisa is 1.234 rial', () {
      expect(
        EcrAmount.fromMinorUnits(1234, minorUnitDigits: 3).toString(),
        '1.234',
      );
    });

    test('the currency decides where the point falls', () {
      expect(
        EcrAmount.fromMinorUnits(123, minorUnitDigits: 2).toString(),
        '1.23',
      );
      expect(
        EcrAmount.fromMinorUnits(123, minorUnitDigits: 0).toString(),
        '123',
      );
    });

    test('zero reads as zero, not as the padding it arrived in', () {
      expect(
        EcrAmount.fromMinorUnits(0, minorUnitDigits: 3).toString(),
        '0.000',
      );
    });

    test('a negative amount is refused — a terminal never returns one', () {
      expect(
        () => EcrAmount.fromMinorUnits(-1, minorUnitDigits: 3),
        throwsA(isA<EcrArgumentError>()),
      );
    });
  });

  group('equality is by value, not by how it was written', () {
    test('1.2 and 1.200 are the same amount', () {
      expect(EcrAmount.parse('1.2'), EcrAmount.parse('1.200'));
      expect(EcrAmount.parse('1.2').hashCode, EcrAmount.parse('1.200').hashCode);
    });

    test('but each keeps the digits it was given', () {
      expect(EcrAmount.parse('1.2').toString(), '1.2');
      expect(EcrAmount.parse('1.200').toString(), '1.200');
    });

    test('zero written three ways is one amount', () {
      expect(EcrAmount.parse('0'), EcrAmount.parse('0.000'));
      expect(EcrAmount.parse('0').hashCode, EcrAmount.parse('0.00').hashCode);
    });

    test('ordering compares value', () {
      final List<EcrAmount> amounts = <EcrAmount>[
        EcrAmount.parse('10'),
        EcrAmount.parse('1.999'),
        EcrAmount.parse('2'),
      ]..sort();

      expect(
        amounts.map((EcrAmount a) => a.toString()).toList(),
        <String>['1.999', '2', '10'],
      );
    });

    test('isZero does not care about scale', () {
      expect(EcrAmount.parse('0.000').isZero, isTrue);
      expect(EcrAmount.parse('0.001').isZero, isFalse);
    });
  });

  test('the wire form is the major-unit string, unchanged', () {
    expect(EcrAmount.parse('1.234').toWireString(), '1.234');
    expect(EcrAmount.parse('0.500').toWireString(), '0.500');
  });
}
