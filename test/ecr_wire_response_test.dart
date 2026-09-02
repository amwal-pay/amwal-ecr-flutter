import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EcrWireResponse.displayMessageFromRaw', () {
    test('prefers errorList over message', () {
      const String raw = '''
{
  "success": false,
  "responseCode": "51",
  "message": "Declined",
  "errorList": ["Insufficient funds"]
}
''';

      expect(
        EcrWireResponse.displayMessageFromRaw(raw, fallback: 'fallback'),
        'Insufficient funds',
      );
    });

    test('reads message from nested ecrResponse', () {
      const String raw = '''
{
  "ecrResponse": {
    "success": false,
    "responseCode": "05",
    "message": "Do not honour"
  }
}
''';

      expect(
        EcrWireResponse.displayMessageFromRaw(raw, fallback: 'fallback'),
        'Do not honour',
      );
    });

    test('falls back when raw is empty or invalid', () {
      expect(
        EcrWireResponse.displayMessageFromRaw('', fallback: 'nothing'),
        'nothing',
      );
      expect(
        EcrWireResponse.displayMessageFromRaw('not json', fallback: 'nothing'),
        'nothing',
      );
    });

    test('reads legacy responseMessage at the top level', () {
      const String raw = '''
{
  "approved": false,
  "responseCode": "96",
  "responseMessage": "Terminal busy"
}
''';

      expect(
        EcrWireResponse.displayMessageFromRaw(raw, fallback: 'fallback'),
        'Terminal busy',
      );
    });
  });
}
