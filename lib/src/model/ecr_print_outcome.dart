import 'dart:typed_data';

/// App-to-app PRINT outcome. Same wire values as the payment app
/// (`amwal.ecr.printStatus` = SUCCESSFUL | FAILED).
enum EcrPrintStatus {
  /// The terminal accepted and printed the image.
  successful,

  /// The print did not happen (wrong width, missing app, printer fault, …).
  failed;

  /// Wire spelling for `amwal.ecr.printStatus`.
  String get wire => name.toUpperCase();

  /// Whether this status means the print completed.
  bool get isSuccess => this == EcrPrintStatus.successful;

  /// Reads a channel / Intent status string, falling back to [ok] when absent.
  static EcrPrintStatus fromWire(String? raw, {bool? ok}) {
    switch (raw?.trim().toUpperCase()) {
      case 'SUCCESSFUL':
      case 'SUCCESS':
      case 'OK':
        return EcrPrintStatus.successful;
      case 'FAILED':
      case 'FAIL':
      case 'ERROR':
        return EcrPrintStatus.failed;
      default:
        return ok == true ? EcrPrintStatus.successful : EcrPrintStatus.failed;
    }
  }

  /// Maps a boolean ok flag to [successful] / [failed].
  static EcrPrintStatus of(bool ok) =>
      ok ? EcrPrintStatus.successful : EcrPrintStatus.failed;
}

/// Print answer: [status] and [message] are independent — never merge them
/// into one string for the channel or for UI.
final class EcrPrintOutcome {
  /// Creates an outcome with separate [status] and [message] fields.
  const EcrPrintOutcome({required this.status, this.message = ''});

  /// Convenience for a successful print.
  factory EcrPrintOutcome.successful([String message = '']) =>
      EcrPrintOutcome(status: EcrPrintStatus.successful, message: message);

  /// Convenience for a failed print.
  factory EcrPrintOutcome.failed([String message = '']) =>
      EcrPrintOutcome(status: EcrPrintStatus.failed, message: message);

  /// Builds from channel / Intent fields without merging them.
  factory EcrPrintOutcome.from({
    required bool ok,
    required String message,
    String? statusWire,
  }) =>
      EcrPrintOutcome(
        status: EcrPrintStatus.fromWire(statusWire, ok: ok),
        message: message,
      );

  /// Wire / channel status (`SUCCESSFUL` or `FAILED`).
  final EcrPrintStatus status;

  /// Human-readable detail. Independent of [status] — never a combined string.
  final String message;

  /// Whether [status] is [EcrPrintStatus.successful].
  bool get isSuccess => status.isSuccess;

  /// Max printable bitmap width on Amwal POS printers (matches native reprint).
  static const int printerWidth = 384;

  /// Max encoded image payload (PNG/JPEG bytes) accepted for PRINT.
  static const int printerMaxBytes = 15 * 1024 * 1024; // 15 MiB

  /// Ensures [imagePng] is non-empty, at most [printerMaxBytes], and when it
  /// is a PNG that its IHDR width is exactly [printerWidth]. Height may be any
  /// positive value.
  ///
  /// Returns null when valid. JPEG and other formats are left for the Android
  /// host to decode after the size check — this rejects empty / oversized
  /// payloads and wrong-width PNGs before the channel hop.
  static String? validatePrintImage(Uint8List? imagePng) {
    if (imagePng == null || imagePng.isEmpty) {
      return 'Print image is required (width must be ${printerWidth}px)';
    }
    if (imagePng.length > printerMaxBytes) {
      return 'Print image size must not exceed '
          '${printerMaxBytes ~/ (1024 * 1024)} MB '
          '(was ${imagePng.length} bytes)';
    }
    if (!_looksLikePng(imagePng)) return null;
    if (imagePng.length < 24) {
      return 'Print image could not be decoded';
    }
    final int width = (imagePng[16] << 24) |
        (imagePng[17] << 16) |
        (imagePng[18] << 8) |
        imagePng[19];
    final int height = (imagePng[20] << 24) |
        (imagePng[21] << 16) |
        (imagePng[22] << 8) |
        imagePng[23];
    if (width <= 0 || height <= 0) {
      return 'Print image could not be decoded';
    }
    if (width != printerWidth) {
      return 'Print image width must be ${printerWidth}px '
          '(was ${width}x$height)';
    }
    return null;
  }

  static bool _looksLikePng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;

  @override
  String toString() =>
      'EcrPrintOutcome(status: ${status.wire}, message: $message)';
}
