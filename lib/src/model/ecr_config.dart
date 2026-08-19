import 'ecr_errors.dart';

/// How this till identifies itself and how it talks to a terminal.
///
/// The defaults describe an Omani deployment on the standard port; a till in
/// another currency or on another port overrides them. Mirrors `EcrConfig` in
/// the Android SDK, with [Duration] where Kotlin has `kotlin.time.Duration`.
final class EcrConfig {
  /// Throws [EcrArgumentError] when a value is outside what the protocol
  /// allows, at construction rather than at the first transaction.
  EcrConfig({
    this.ecrId = 'ECR01',
    this.currencyCode = '512',
    this.minorUnitDigits = 3,
    this.port = defaultPort,
    this.connectTimeout = const Duration(seconds: 10),
    this.responseTimeout = const Duration(seconds: 120),
    this.probeTimeout = const Duration(seconds: 3),
    this.secureHashKey = '',
    this.autoInquireOnFailure = true,
  }) {
    if (minorUnitDigits < 0 || minorUnitDigits > 4) {
      throw EcrArgumentError(
        'minorUnitDigits must be between 0 and 4, got $minorUnitDigits',
      );
    }
    if (port < 1 || port > 65535) {
      throw EcrArgumentError('port must be between 1 and 65535, got $port');
    }
    if (secureHashKey.isNotEmpty && !_isValidSecret(secureHashKey)) {
      // Caught here rather than at the first sale: a key with a stray space or a
      // missing character otherwise fails on the shop floor, as a decline the
      // cashier cannot explain.
      throw const EcrArgumentError(
        'secureHashKey must be an even-length hex string of at least '
        '$_minSecretLength characters, or empty to send unsigned messages',
      );
    }
    for (final (String name, Duration value) in <(String, Duration)>[
      ('connectTimeout', connectTimeout),
      ('responseTimeout', responseTimeout),
      ('probeTimeout', probeTimeout),
    ]) {
      if (value <= Duration.zero) {
        throw EcrArgumentError('$name must be positive, got $value');
      }
    }
  }

  /// The port Amwal POS terminals listen on for ECR requests.
  static const int defaultPort = 9100;

  /// 64 bits is the shortest key worth calling a secret.
  static const int _minSecretLength = 16;

  /// Identifies this cash register to the terminal, and appears on the
  /// terminal's records of the transaction.
  final String ecrId;

  /// ISO 4217 numeric code, e.g. `512` for OMR.
  final String currencyCode;

  /// Decimal places the currency has: 3 for OMR, 2 for USD, 0 for JPY.
  ///
  /// Amounts travel as minor units, so this decides how 1.234 is written.
  /// Nothing cross-checks it against [currencyCode] — getting it wrong sends
  /// every amount off by a factor of ten and neither side will object.
  final int minorUnitDigits;

  /// The terminal's ECR listener port.
  final int port;

  /// How long to wait for the terminal to accept a connection.
  final Duration connectTimeout;

  /// How long to wait for the result once the request is sent.
  ///
  /// Generous by default: the cardholder has to present a card and may be
  /// asked for a PIN. Ninety seconds is not unusual.
  final Duration responseTimeout;

  /// How long a reachability probe waits.
  ///
  /// Short on purpose — a terminal on the same network answers a handshake in
  /// milliseconds or is not there at all.
  final Duration probeTimeout;

  /// The secret this till shares with the terminal, as hex.
  ///
  /// Set it and every request is signed and every response is checked. Required
  /// in practice: a terminal refuses everything it cannot verify, so a till
  /// without the key is answered with a security violation and nothing else.
  /// Amwal issues it per terminal — it is not a value to invent, and not one to
  /// commit to a repository or to ship inside an app bundle.
  ///
  /// An answer that cannot be shown to have come from the terminal is reported
  /// as [EcrUnauthenticated], which leaves the outcome unknown — never as a
  /// decline. The signing itself is done by the native SDK, where the wire
  /// format lives.
  ///
  /// Must be an even-length hex string of at least 16 characters, or empty to
  /// send unsigned messages; anything else throws [EcrArgumentError] here.
  final String secureHashKey;

  /// Whether a transaction whose answer never arrived is followed by an inquiry,
  /// so the till learns what actually happened instead of being left to guess.
  ///
  /// On by default, and safe: an inquiry reads and nothing more, so repeating
  /// one changes nothing — unlike sending the sale again, which charges the
  /// cardholder twice and is never done automatically. The finding arrives on
  /// `EcrFailed.recovered`.
  ///
  /// Turn it off only if the till runs its own reconciliation and would rather
  /// not have the extra round trip on a failure.
  final bool autoInquireOnFailure;

  /// Whether this till signs what it sends.
  bool get signsMessages => secureHashKey.isNotEmpty;

  /// A copy with the named fields replaced.
  EcrConfig copyWith({
    String? ecrId,
    String? currencyCode,
    int? minorUnitDigits,
    int? port,
    Duration? connectTimeout,
    Duration? responseTimeout,
    Duration? probeTimeout,
    String? secureHashKey,
    bool? autoInquireOnFailure,
  }) {
    return EcrConfig(
      ecrId: ecrId ?? this.ecrId,
      currencyCode: currencyCode ?? this.currencyCode,
      minorUnitDigits: minorUnitDigits ?? this.minorUnitDigits,
      port: port ?? this.port,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      responseTimeout: responseTimeout ?? this.responseTimeout,
      probeTimeout: probeTimeout ?? this.probeTimeout,
      secureHashKey: secureHashKey ?? this.secureHashKey,
      autoInquireOnFailure: autoInquireOnFailure ?? this.autoInquireOnFailure,
    );
  }

  static bool _isValidSecret(String key) =>
      key.length >= _minSecretLength &&
      key.length.isEven &&
      RegExp(r'^[0-9a-fA-F]+$').hasMatch(key);

  @override
  bool operator ==(Object other) =>
      other is EcrConfig &&
      other.ecrId == ecrId &&
      other.currencyCode == currencyCode &&
      other.minorUnitDigits == minorUnitDigits &&
      other.port == port &&
      other.connectTimeout == connectTimeout &&
      other.responseTimeout == responseTimeout &&
      other.probeTimeout == probeTimeout &&
      other.secureHashKey == secureHashKey &&
      other.autoInquireOnFailure == autoInquireOnFailure;

  @override
  int get hashCode => Object.hash(
        ecrId,
        currencyCode,
        minorUnitDigits,
        port,
        connectTimeout,
        responseTimeout,
        probeTimeout,
        secureHashKey,
        autoInquireOnFailure,
      );

  @override
  String toString() => 'EcrConfig(ecrId: $ecrId, currencyCode: $currencyCode, '
      'minorUnitDigits: $minorUnitDigits, port: $port, '
      // The key itself is never printed. A toString ends up in logs, crash
      // reports and bug tickets, and the secret must not travel with them.
      'signed: $signsMessages)';
}
