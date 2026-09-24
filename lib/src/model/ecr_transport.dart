import 'package:flutter/foundation.dart';

/// How the till reaches the terminal.
///
/// Mirrors the `ecrMode` a terminal's TMS profile carries. Only Wi‑Fi opens an
/// IP listener; USB cable talks over AOA with no address; [bluetooth] and
/// [webService] are driven by other machinery (Web Service by this plugin's
/// REST path).
///
/// Naming an unsupported transport is not an error at construction — a till
/// reads the mode from a profile it does not control. It becomes a typed
/// failure at the moment an operation is attempted, so the caller handles it
/// alongside every other reason a transaction did not happen.
enum EcrTransport {
  /// `ecrMode` 1. USB cable (Android Open Accessory). No IP.
  usbCable(wireValue: 1, isIpTransport: false),

  /// `ecrMode` 2. Wireless IP; the SDK connects over TCP.
  wifi(wireValue: 2, isIpTransport: true),

  /// `ecrMode` 3. Not carried over IP, so this SDK cannot drive it.
  bluetooth(wireValue: 3, isIpTransport: false),

  /// `ecrMode` 4. The terminal is driven from the payment host over REST.
  webService(wireValue: 4, isIpTransport: false),

  /// `ecrMode` 5. The terminal **is** this device: the till hands the request
  /// to the Amwal payment app installed beside it and waits for the result.
  ///
  /// The only transport with no address. [EcrTerminal.host] carries the
  /// payment app's application id instead, and reachability is whether that
  /// app is installed and will accept a request — not whether anything
  /// answers on a socket.
  appToApp(wireValue: 5, isIpTransport: false);

  const EcrTransport({required this.wireValue, required this.isIpTransport});

  /// The `ecrMode` integer this corresponds to in a TMS profile.
  final int wireValue;

  /// Whether the terminal listens on a socket for this transport.
  ///
  /// True only for [wifi]. USB cable is not IP.
  final bool isIpTransport;

  /// Whether the till reaches the terminal down a USB cable.
  bool get isUsbCable => this == EcrTransport.usbCable;

  /// Whether the terminal is the device this till is running on.
  bool get isAppToApp => this == EcrTransport.appToApp;

  /// Whether a till can ask, before sending anything, if the terminal is
  /// there.
  ///
  /// Named rather than written as "not web service" at each call site, because
  /// the answer is not simply "is it a socket": app to app can be checked
  /// without sending anything, and Web Service cannot be checked at all.
  bool get hasReachabilityProbe =>
      isIpTransport || isUsbCable || isAppToApp;

  /// Whether an e-receipt can be fetched over this transport.
  ///
  /// App to app included. The terminal keeps the same record and answers the
  /// same request over it — the Kotlin SDK has always allowed this, and a
  /// terminal that behaved differently depending on which SDK asked is the one
  /// thing this package exists to prevent.
  bool get supportsReceipt => isIpTransport || isUsbCable || isAppToApp;

  /// Whether the terminal can be asked what it is over this transport.
  ///
  /// **App to app is excluded, deliberately.** A sign-on there costs a visible
  /// handover — this app to the background, the payment app to the front — to
  /// learn something no operator asked for. Nothing is lost by not asking: a
  /// request the profile does not permit is refused anyway, and the refusal
  /// carries the same profile a sign-on would have. The native SDK makes the
  /// same exclusion for the same reason.
  ///
  /// Web Service is excluded too, for a different one: there the terminal is
  /// reached through Amwal rather than addressed directly, so a till configured
  /// for it already knows what a sign-on would tell it about the link.
  bool get supportsSignOn => isIpTransport || isUsbCable;

  /// Whether this Flutter plugin can drive transactions over this transport.
  ///
  /// [usbCable] is implemented on Android only; on iOS and Windows the host
  /// returns a typed unsupported failure if a call still reaches it.
  bool get isSupportedByPlugin {
    switch (this) {
      case EcrTransport.wifi:
      case EcrTransport.webService:
        return true;
      case EcrTransport.usbCable:
      case EcrTransport.appToApp:
        return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      case EcrTransport.bluetooth:
        return false;
    }
  }

  /// The transport for a TMS `ecrMode`, or `null` when the profile carries a
  /// value this version does not know.
  static EcrTransport? fromWireValue(int value) {
    for (final EcrTransport transport in EcrTransport.values) {
      if (transport.wireValue == value) return transport;
    }
    return null;
  }

  /// The name used on the platform channel.
  ///
  /// [usbCable] is `"usb_cable"` — not [Enum.name] (`usbCable`).
  String get channelName => switch (this) {
        EcrTransport.usbCable => 'usb_cable',
        EcrTransport.appToApp => 'app_to_app',
        _ => name,
      };

  /// The transport named on the channel, or `null` when unrecognised.
  ///
  /// Accepts `"web_service"` as an alias for [webService]. The primary channel
  /// spelling remains `"webService"`.
  static EcrTransport? fromChannelName(String name) {
    if (name == 'web_service') return EcrTransport.webService;
    for (final EcrTransport transport in EcrTransport.values) {
      if (transport.channelName == name) return transport;
    }
    return null;
  }
}
