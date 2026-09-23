import 'dart:convert';
import 'dart:typed_data';

import 'package:amwal_ecr/src/dart_io/ecr_frames.dart';
import 'package:amwal_ecr/src/dart_io/ecr_message.dart';
import 'package:amwal_ecr/src/dart_io/secure_hash.dart';
import 'package:amwal_ecr/src/dart_io/web_service_secure_hash.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ecr_test_configs.dart';

void main() {
  group('EcrFrames', () {
    test('wraps a body with a two-byte big-endian length', () {
      final Uint8List packet = EcrFrames.wrap(utf8.encode('{"a":1}'));
      expect(packet[0], 0);
      expect(packet[1], 7);
      expect(utf8.decode(packet.sublist(2)), '{"a":1}');
    });

    test('bodyLength reads the header', () {
      expect(EcrFrames.bodyLength(<int>[0x00, 0x0A]), 10);
      expect(EcrFrames.bodyLength(<int>[0x01, 0x00]), 256);
    });

    test('refuses a body longer than the header can describe', () {
      expect(
        () => EcrFrames.wrap(Uint8List(0x10000)),
        throwsA(isA<EcrFrameException>()),
      );
    });

    test('readBody reconstitutes one framed message', () async {
      final Uint8List packet = EcrFrames.wrap(utf8.encode('{"ok":true}'));
      final Uint8List body =
          await EcrFrames.readBody(Stream<List<int>>.value(packet));
      expect(utf8.decode(body), '{"ok":true}');
    });
  });

  group('SecureHash (LAN)', () {
    final String key = EcrTestConfigs.SECURE_HASH_KEY_ECR_WIFI;
    final String otherKey = EcrTestConfigs.SECURE_HASH_KEY_ECR_WIFI_OTHER;

    test('fields are signed in sorted order', () {
      expect(
        SecureHash.compose(<String, Object?>{
          'messageType': 'SALE',
          'amount': '000000001234',
          'version': 1,
        }),
        'amount=000000001234&messageType=SALE&version=1',
      );
    });

    test('the signature field is never part of what is signed', () {
      final Map<String, Object?> unsigned = <String, Object?>{'amount': '1'};
      final Map<String, Object?> signed = <String, Object?>{
        'amount': '1',
        SecureHash.field: 'WHATEVER',
      };
      expect(SecureHash.compose(unsigned), SecureHash.compose(signed));
    });

    test('nested values and nulls are left out', () {
      expect(
        SecureHash.compose(<String, Object?>{
          'amount': '1',
          'ecrResponse': <String, Object?>{'data': 'x'},
          'list': <int>[1, 2],
          'missing': null,
        }),
        'amount=1',
      );
    });

    test('booleans and numbers are signed as they are written', () {
      expect(
        SecureHash.compose(<String, Object?>{'approved': true, 'version': 1}),
        'approved=true&version=1',
      );
      expect(SecureHash.compose(<String, Object?>{'flag': 1}), 'flag=1');
      expect(SecureHash.compose(<String, Object?>{'flag': true}), 'flag=true');
    });

    test('a signature verifies against the key that made it', () {
      final Map<String, Object?> body = <String, Object?>{
        'amount': '000000001234',
      };
      final String hash = SecureHash.sign(SecureHash.compose(body), key);
      final Map<String, Object?> signed = <String, Object?>{
        ...body,
        SecureHash.field: hash,
      };
      expect(SecureHash.verify(signed, key), isTrue);
      expect(SecureHash.verify(signed, otherKey), isFalse);
    });

    test('changing the amount invalidates the signature', () {
      final String signature = SecureHash.sign(
        SecureHash.compose(<String, Object?>{'amount': '000000001234'}),
        key,
      );
      expect(
        SecureHash.verify(
          <String, Object?>{
            'amount': '000000009999',
            SecureHash.field: signature,
          },
          key,
        ),
        isFalse,
      );
    });

    test('an unsigned message never verifies', () {
      expect(
        SecureHash.verify(<String, Object?>{'amount': '1'}, key),
        isFalse,
      );
    });

    test('a key that is not hex is refused rather than read as text', () {
      expect(
        () => SecureHash.sign('a=1', 'not-hex!!'),
        throwsA(isA<FormatException>()),
      );
    });

    test('the digest is HMAC-SHA256 as uppercase hex', () {
      final String signature = SecureHash.sign('amount=000000001234', key);
      expect(signature.length, 64);
      expect(RegExp(r'^[0-9A-F]+$').hasMatch(signature), isTrue);
      expect(signature, SecureHash.sign('amount=000000001234', key));
    });

    test('newNonce is 32 uppercase hex characters', () {
      final String nonce = SecureHash.newNonce();
      expect(nonce.length, 32);
      expect(RegExp(r'^[0-9A-F]+$').hasMatch(nonce), isTrue);
    });
  });

  group('WebServiceSecureHash', () {
    final String key = EcrTestConfigs.SECURE_HASH_KEY_WEBSERVICE;

    test('compose excludes secureHashValue', () {
      expect(
        WebServiceSecureHash.compose(<String, Object?>{
          'amount': '1',
          WebServiceSecureHash.field: 'ABC',
          'version': 1,
        }),
        'amount=1&version=1',
      );
    });

    test('withHash adds an uppercase HMAC over the sorted payload', () {
      final Map<String, Object?> signed = WebServiceSecureHash.withHash(
        <String, Object?>{
          'amount': '000000001234',
          'messageType': 'SALE',
          'version': 1,
        },
        key,
      );
      final String hash = signed[WebServiceSecureHash.field]! as String;
      expect(hash.length, 64);
      expect(RegExp(r'^[0-9A-F]+$').hasMatch(hash), isTrue);
      expect(
        hash,
        WebServiceSecureHash.calcHash(
          'amount=000000001234&messageType=SALE&version=1',
          key,
        ),
      );
    });

    test('never prints the secret in error paths', () {
      // Placeholder assertion: FormatException for a bad key must not embed it.
      try {
        WebServiceSecureHash.withHash(
          <String, Object?>{'a': '1'},
          'not-hex',
        );
        fail('expected FormatException');
      } on FormatException catch (error) {
        expect(error.message, isNot(contains('not-hex')));
        expect(error.toString(), isNot(contains(key)));
      }
    });
  });

  group('EcrMessage helpers', () {
    test('minorUnits pads to twelve digits', () {
      expect(EcrMessage.minorUnits(null, 3), '000000000000');
    });

    test('paddedStan zero-pads operator receipt numbers', () {
      expect(EcrMessage.paddedStan('24'), '000024');
      expect(EcrMessage.paddedStan('000215'), '000215');
      expect(EcrMessage.paddedStan('000000'), '');
    });

    test('merchant reference rejects separators used in signing', () {
      expect(
        () => EcrMessage.resolveMerchantReference('order&1'),
        throwsA(isA<Object>()),
      );
      expect(
        () => EcrMessage.resolveMerchantReference('x' * 33),
        throwsA(isA<Object>()),
      );
      expect(EcrMessage.resolveMerchantReference('ORDER-1'), 'ORDER-1');
    });
  });
}
