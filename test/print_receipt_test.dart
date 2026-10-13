import 'dart:typed_data';

import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/amwal_ecr_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'platform/fake_host.dart';

/// PRINT is app-to-app only. These pin down the gates that keep Wi‑Fi / USB /
/// Web Service from ever starting an intent, and the width / size checks that
/// stop a wrong image leaving the device.
void main() {
  late FakeEcrHost host;

  setUp(() => host = FakeEcrHost());
  tearDown(() {
    host.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  /// Minimal valid PNG IHDR with the given pixel size (empty IDAT is fine for
  /// the Dart IHDR width check; Android BitmapFactory is tested separately).
  Uint8List pngOfWidth(int width, {int height = 10}) {
    final BytesBuilder out = BytesBuilder();
    out.add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    out.add(<int>[0, 0, 0, 13]); // IHDR length
    out.add('IHDR'.codeUnits);
    out.add(<int>[
      (width >> 24) & 0xFF,
      (width >> 16) & 0xFF,
      (width >> 8) & 0xFF,
      width & 0xFF,
      (height >> 24) & 0xFF,
      (height >> 16) & 0xFF,
      (height >> 8) & 0xFF,
      height & 0xFF,
      8,
      2,
      0,
      0,
      0,
    ]);
    out.add(<int>[0, 0, 0, 0]); // CRC placeholder
    return out.toBytes();
  }

  group('non-app-to-app', () {
    test('Wi‑Fi refuses before the host is called', () async {
      final EcrTerminal terminal = EcrTerminal(
        host: '192.168.1.50',
        serialNumber: 'P653200085189',
        transport: EcrTransport.wifi,
        platform: MethodChannelAmwalEcr(channel: FakeEcrHost.channel),
      );

      final EcrPrintOutcome outcome = await terminal.printReceipt(
        imagePng: pngOfWidth(384),
      );

      expect(outcome.isSuccess, isFalse);
      expect(outcome.status, EcrPrintStatus.failed);
      expect(outcome.message, contains('app to app'));
      expect(host.calls, isEmpty);
    });

    test('Web Service refuses before the host is called', () async {
      final EcrTerminal terminal = EcrTerminal(
        host: '',
        serialNumber: 'P653200085189',
        transport: EcrTransport.webService,
        config: EcrConfig(merchantId: 'm', terminalId: 't'),
        platform: MethodChannelAmwalEcr(channel: FakeEcrHost.channel),
      );

      final EcrPrintOutcome outcome = await terminal.printReceipt(
        imagePng: pngOfWidth(384),
      );

      expect(outcome.status, EcrPrintStatus.failed);
      expect(host.calls, isEmpty);
    });
  });

  group('width validation', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('wrong PNG width fails without calling the host', () async {
      final EcrTerminal terminal = EcrTerminal.appToApp(
        serialNumber: 'P653200085189',
        platform: MethodChannelAmwalEcr(channel: FakeEcrHost.channel),
      );

      final EcrPrintOutcome outcome = await terminal.printReceipt(
        imagePng: pngOfWidth(200),
      );

      expect(outcome.isSuccess, isFalse);
      expect(outcome.message, contains('384'));
      expect(outcome.message, contains('200'));
      expect(host.calls, isEmpty);
    });

    test('empty image fails without calling the host', () async {
      final EcrTerminal terminal = EcrTerminal.appToApp(
        serialNumber: 'P653200085189',
        platform: MethodChannelAmwalEcr(channel: FakeEcrHost.channel),
      );

      final EcrPrintOutcome outcome = await terminal.printReceipt(
        imagePng: Uint8List(0),
      );

      expect(outcome.status, EcrPrintStatus.failed);
      expect(outcome.message, contains('required'));
      expect(host.calls, isEmpty);
    });
  });

  group('app-to-app on Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('forwards a valid image and keeps status and message separate',
        () async {
      host.answer(EcrMethods.printReceipt, <String, Object?>{
        EcrPrintKeys.status: 'SUCCESSFUL',
        EcrPrintKeys.message: 'Printed',
        EcrPrintKeys.ok: true,
      });

      final EcrTerminal terminal = EcrTerminal.appToApp(
        serialNumber: 'P653200085189',
        platform: MethodChannelAmwalEcr(channel: FakeEcrHost.channel),
      );
      final Uint8List image = pngOfWidth(384);

      final EcrPrintOutcome outcome = await terminal.printReceipt(
        imagePng: image,
        merchantReference: 'ORDER-1',
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.status, EcrPrintStatus.successful);
      expect(outcome.message, 'Printed');
      expect(host.countOf(EcrMethods.printReceipt), 1);
      final Map<Object?, Object?> args =
          host.argumentsOf(EcrMethods.printReceipt);
      expect(args[EcrArgs.transport], 'app_to_app');
      expect(args[EcrArgs.merchantReference], 'ORDER-1');
      expect(args[EcrArgs.receiptImage], image);
    });
  });

  group('EcrPrintOutcome.validatePrintImage', () {
    test('accepts a 384-wide PNG', () {
      expect(EcrPrintOutcome.validatePrintImage(pngOfWidth(384)), isNull);
    });

    test('rejects a non-384 width', () {
      expect(
        EcrPrintOutcome.validatePrintImage(pngOfWidth(100, height: 50)),
        contains('100x50'),
      );
    });

    test('rejects an image larger than 15 MB', () {
      final Uint8List oversized = Uint8List(
        EcrPrintOutcome.printerMaxBytes + 1,
      );
      oversized[0] = 0x89;
      oversized[1] = 0x50; // P
      oversized[2] = 0x4E; // N
      oversized[3] = 0x47; // G
      expect(
        EcrPrintOutcome.validatePrintImage(oversized),
        contains('15 MB'),
      );
    });
  });
}
