import '../dart_io/dart_io_amwal_ecr_platform.dart';
import '../platform/amwal_ecr_platform.dart';

/// Windows dartPluginClass registration for `amwal_ecr`.
///
/// Flutter loads this file only on Windows via `dartPluginClass` /
/// `dartFileName` in `pubspec.yaml`, so `dart:io` usage in the Dart IO host
/// never reaches web builds.
class AmwalEcrWindows {
  /// Installs the pure-Dart ECR platform implementation.
  static void registerWith() {
    AmwalEcrPlatform.instance = DartIoAmwalEcrPlatform();
  }
}
