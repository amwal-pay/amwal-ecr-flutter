import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the pubspec platform stanza that Codemagic also checks before
/// `dart pub publish`. A release without `windows:` would still publish an
/// Android/iOS-only package and break Windows integrators silently.
void main() {
  test('pubspec declares the Windows dartPluginClass host', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains(RegExp(r'^\s*windows:\s*$', multiLine: true)),
    );
    expect(pubspec, contains('dartPluginClass: AmwalEcrWindows'));
    expect(
      pubspec,
      contains('dartFileName: src/windows/amwal_ecr_windows.dart'),
    );
    expect(File('lib/src/windows/amwal_ecr_windows.dart').existsSync(), isTrue);
    expect(
      File('lib/src/dart_io/dart_io_amwal_ecr_platform.dart').existsSync(),
      isTrue,
    );
  });
}
