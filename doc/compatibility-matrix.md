# Compatibility matrix

What this wrapper is built against, what it runs on, and every place the
platforms are not the same.

Read the last sections before shipping. "Equivalent on Android, iOS, and
Windows" is a claim with exceptions, and they are written down here rather than
discovered.

---

## 1. Versions

### This package

| | |
|---|---|
| `amwal_ecr` | 0.3.0 |
| Dart SDK | `^3.5.0` — the API uses sealed classes and pattern matching |
| Flutter | `>=3.22.0` |
| Protocol version | `1` (the `version` field in every request) |

The two native providers must be upgraded **together**. They speak the same wire
format, and the 1.0.4 / 0.2.0 line renamed the field naming a transaction from
`requestId` to `merchantReference`; a host on the older line is not missing a
field, it fails to be understood by a current terminal.

### Native providers

| Platform | Provider | Version | Source |
|---|---|---|---|
| Android | `com.amwal-pay:ecr-sdk` | **1.0.5** (local / project), exact | Maven Central / sibling `:ecr-sdk` |
| iOS | `AmwalECR` | **`0.2.1`** | [CocoaPods](https://github.com/amwal-pay/AmwalECR-iOS-CocoaPods), [SwiftPM](https://github.com/amwal-pay/AmwalECR-iOS-SPM) |
| Windows | Pure-Dart `DartIoAmwalEcrPlatform` | ships in this package | No separate native artifact |

Android and iOS providers expose **`EcrSessions.open` / `EcrOpenedSession`**. The
Flutter hosts call that API so LAN, USB cable, and Web Service share one
dispatch path. Windows implements the same Dart session API without a native
SDK binary.

Both mobile providers are published SDKs that native apps use directly, without
Flutter. On Android and iOS this package is a bridge over them. On Windows the
same Dart API is backed by a pure-Dart protocol engine (`lib/src/dart_io/`)
that mirrors those SDKs' LAN and Web Service behaviour.

**The Android version is pinned, not ranged.** An ECR SDK that changes how an
outcome is reported changes what a till books, and that is not something to pick
up by surprise on a dependency refresh. Raising it is a deliberate change: bump
`android/build.gradle`, re-run the contract tests, and note it in the changelog.

**The iOS version is ranged to the patch line** — `~> 0.2.0` in
`ios/amwal_ecr.podspec`, `.upToNextMinor(from: "0.2.0")` in
`ios/amwal_ecr/Package.swift`. Not because it matters less, but because an app
can hold a native till of its own against the same pod and the two must resolve
together; an exact pin would be an integrator's problem to unpick. The range is
safe by the release policy, which gives a major version to anything that changes
what an outcome means, so `0.2.x` cannot report differently from what this
bridge is contract-tested against. The two files must always name the same
range.

### The iOS seam

`EcrTerminalPort`, in `ios/amwal_ecr/Sources/amwal_ecr/EcrTerminalPort.swift`,
is the whole of what this package asks of an ECR implementation.
`AmwalECR.EcrTerminal` satisfies it as it is; the conformance is one line.
Swapping in a different implementation — a fake in a test, a future SDK — means
conforming its terminal type and changing `makeNativeTerminal`. The handler, the
mapping, the channel contract and the whole Dart API are untouched by that
change, and the Dart tests will not notice it happened.

---

## 2. Platforms

| | Minimum | Notes |
|---|---|---|
| Android | API 21 | Plain TCP on the local network; nothing needs newer |
| Android compile SDK | 34 | |
| Android/Kotlin JVM target | 17 | The ECR SDK is a Java 17 library |
| iOS | 12.0 | The floor of `AmwalECR`, both podspecs and both `Package.swift` files — raise them together |
| Swift | 5.5 | |
| Windows | Windows 10 | Pure-Dart `dart:io` TCP + HTTPS; no native ECR plugin binary. Build only on a Windows host (Visual Studio + Desktop C++). |

| Platform | Supported |
|---|---|
| Android | ✔ |
| iOS | ✔ |
| Windows | ✔ — pure-Dart host (`AmwalEcrWindows` / `DartIoAmwalEcrPlatform`): Wi‑Fi TCP + Web Service. USB cable ✘, app to app ✘ |
| macOS, Linux, Web | ✘ — no host is registered, so every call answers `EcrUnsupported` |

A missing host is reported as `EcrUnsupported` with the message naming a
rebuild, rather than as a thrown `MissingPluginException`, so an app running on
an unsupported platform degrades instead of crashing.

**Example apps** that use `flutter_secure_storage` on Windows also need Visual
Studio **C++ ATL** (that plugin's native requirement — not part of
`amwal_ecr` itself). See [`example/README.md`](../example/README.md).

---

## 3. Transports

`EcrTransport` mirrors the `ecrMode` a terminal's TMS profile carries.

| `EcrTransport` | `ecrMode` | Android | iOS | Windows | Behaviour |
|---|---|---|---|---|---|
| `usbCable` (`usb_cable`) | 1 | ✔ | ✘ | ✘ | USB AOA cable; typed unsupported on iOS / Windows |
| `wifi` | 2 | ✔ | ✔ | ✔ | TCP to the terminal |
| `bluetooth` | 3 | ✘ | ✘ | ✘ | `EcrUnsupported`, nothing sent |
| `webService` | 4 | ✔ | ✔ | ✔ | REST / Hub |
| `appToApp` (`app_to_app`) | 5 | ✔ | ✘ | ✘ | The Amwal payment app on this device; typed unsupported on iOS / Windows |

`ecrMode` `1` is USB cable on the channel (`"usb_cable"`). Wire value `1` is
unchanged. There is no Ethernet transport.

Wi‑Fi alone is an IP transport. USB cable carries no IP. Bluetooth remains
unsupported on all platforms. Web Service is driven over REST (native hosts on
mobile; pure Dart `dart:io` HTTP on Windows).

`appToApp` is the only transport whose `host` is **not an address**: it is the
payment app's application id, and `EcrTerminal.appToApp` is the readable way to
say so. An address passed there is refused at construction. It is also the only
one where "reachable" means *installed and willing to accept a request* rather
than *something answered on a socket* — whether a merchant is signed in, and
what the TMS profile permits, are answered by the payment app itself, in a
refusal or a sign-on.

TMS does not send `ecrMode` `5` yet. A terminal whose profile has not been
given it refuses an app-to-app request with the transport check it already has,
and the refusal carries the current profile.

---

## 4. Operations

Every operation behaves identically on Android, iOS, and Windows for the
transports each host supports. This table exists so that "identically" is a
checkable claim rather than an assurance.

| Operation | Android | iOS | Windows | Notes |
|---|---|---|---|---|
| `isReachable` | ✔ | ✔ | ✔ | Bounded by `probeTimeout` |
| `sale` | ✔ | ✔ | ✔ | |
| `voidTransaction` | ✔ | ✔ | ✔ | |
| `refund` | ✔ | ✔ | ✔ | |
| `inquire` | ✔ | ✔ | ✔ | Answered while the terminal is busy |
| `inquireByReference` | ✔ | ✔ | ✔ | The lookup after an answer goes missing |
| `receipt` | ✔ | ✔ | ✔ | |
| `cancel` | ✔ | ✔ | ✔ | Same observable behaviour; different mechanism — see §6 |

| Outcome | Android | iOS | Windows |
|---|---|---|---|
| Approved | ✔ | ✔ | ✔ |
| Partial approval | ✔ | ✔ | ✔ |
| Declined | ✔ | ✔ | ✔ |
| Busy (`96`) | ✔ | ✔ | ✔ |
| Cancelled at the terminal (`17`) | ✔ | ✔ | ✔ |
| Original not found (`25`) | ✔ | ✔ | ✔ |
| Indeterminate (`91`) → `outcomeIsUnknown` | ✔ | ✔ | ✔ |
| Timeout | ✔ | ✔ | ✔ |
| Connection lost | ✔ | ✔ | ✔ |
| Malformed answer | ✔ | ✔ | ✔ |
| Unreachable | ✔ | ✔ | ✔ |
| Cancelled by the caller | ✔ | ✔ | ✔ |
| Unauthenticated answer | ✔ | ✔ | ✔ |
| A lost answer followed up (`EcrFailed.recovered`) | ✔ | ✔ | ✔ |
| `nextStep` on a decline | ✔ | ✔ | ✔ |

USB cable operations apply on Android only; on iOS / Windows they fail as
`EcrUnsupported` before anything is sent.
Over `appToApp` (Android only), with the differences spelled out rather than
implied:

| Operation | `appToApp` | Notes |
|---|---|---|
| `isReachable` | ✔ | Resolves the payment app. Launches nothing |
| `sale` / `voidTransaction` / `refund` | ✔ | The payment app comes to the front and answers |
| `inquire` / `inquireByReference` | ✔ | Never refused locally: the only way out of an unknown outcome |
| `receipt` | ✘ | `EcrReceiptFailed`, nothing sent — there is no link held open to fetch one over |
| `cancel` | ✔ | Stops waiting. It cannot dismiss the payment app's screen — see §6.4 |

| Outcome | Android | iOS |
|---|---|---|
| Approved | ✔ | ✔ |
| Partial approval | ✔ | ✔ |
| Declined | ✔ | ✔ |
| Busy (`96`) | ✔ | ✔ |
| Cancelled at the terminal (`17`) | ✔ | ✔ |
| Original not found (`25`) | ✔ | ✔ |
| Indeterminate (`91`) → `outcomeIsUnknown` | ✔ | ✔ |
| Timeout | ✔ | ✔ |
| Connection lost | ✔ | ✔ |
| Malformed answer | ✔ | ✔ |
| Unreachable | ✔ | ✔ |
| Cancelled by the caller | ✔ | ✔ |
| Unauthenticated answer | ✔ | ✔ | 
| A lost answer followed up (`EcrFailed.recovered`) | ✔ | ✔ |
| `nextStep` on a decline | ✔ | ✔ |

---

## 5. Types, units and nullability across the channel

| Concept | Dart | Channel | Kotlin | Swift |
|---|---|---|---|---|
| Amount out | `EcrAmount` | `String`, **major units**, nullable | `BigDecimal?` | `Decimal?` |
| Amount back | `String` | `String`, **major units** | `String` | `String` |
| Timeouts | `Duration` | `int` **milliseconds** | `kotlin.time.Duration` | `TimeInterval` (seconds) |
| Port, digits | `int` | `int` | `Int` | `Int` |
| Flags | `bool` | `bool` | `Boolean` | `Bool` |
| Identifiers (`terminalId`) | `String` | `String` or `int` | `String` | `String` |
| Absent text | `''` | `null` or `''` | `""` | `""` |
| `originalTerminalId` | `''` | `''` — **never null** | `""` | `""` |
| `merchantReference` | `String` | `String` — `''` means "generate one" | `String` | `String` |
| `secureHashKey` | `String` | `String` — `''` means unsigned | `String` | `String` |
| `nextStep` | `EcrNextStep` | `String`, the protocol's own name | `NextStep` | `EcrNextStep` |
| `recovered` | `EcrInquiry?` | an inquiry map, **absent** when none | `EcrInquiry?` | `EcrInquiry?` |

On Windows there is no Kotlin/Swift channel hop: the Dart types are mapped
straight into the wire protocol by `lib/src/dart_io/`. The same amount, timeout,
and nullability rules apply.

Three rules hold everywhere:

- **Amounts are never doubles.** They cross as decimal strings in major units,
  and are converted to the wire's minor units once (in the native host on
  mobile, in Dart on Windows), with half-up rounding. `1.2345` at three
  decimal places is `1235` on every host.
- **Timeouts cross as whole milliseconds**, because `Duration` and
  `TimeInterval` disagree about units and a key that does not name one invites a
  guess. Hence `connectTimeoutMs`, not `connectTimeout`.
- **A JSON `null` reads as an empty string**, never as the text `"null"`. Every
  field of `EcrTransaction` is non-nullable for that reason.
- **`recovered` is absent, not null, when no follow-up was made.** "Nothing was
  asked" and "the lookup found nothing" are different facts and a till acts on
  them differently, so they are not spelled the same way.

---

## 6. Where the platforms genuinely differ

Differences below are recorded so "not observable from Dart" stays true.
Diagnostics used to be a third mobile-only note; §6.3 covers all three hosts.

### 6.1 What a cancel does to the socket

| | Android | iOS | Windows |
|---|---|---|---|
| Answers the caller | immediately, `EcrCancelled` | immediately, `EcrCancelled` | immediately, `EcrCancelled` |
| The blocked read | keeps running until `responseTimeout`, then its answer is discarded | returns at once — the descriptor is `shutdown` | returns at once — the `Socket` / HTTP client is closed |
| A thread is held | yes, until the read unwinds | no | no |

The Kotlin SDK does not expose its socket, so a cancelled coroutine cannot
interrupt a blocking read; the wrapper answers the caller at once and lets the
orphaned read finish on its own. The Swift implementation owns its socket and
shuts it down. Windows closes the Dart `Socket` or aborts the Hub HTTP call.

**None of them tell the terminal anything.** A cancelled money-moving request
has an unknown outcome on every platform, and is reconciled by an inquiry, never
retried.

### 6.2 Where a malformed secret is caught

| | Android | iOS | Windows |
|---|---|---|---|
| Rejected by | `EcrConfig`'s constructor | `EcrMessage.build`, the last point before the key is used | Dart `EcrConfig` + Dart message build (same rules as mobile) |
| Reported as | `IllegalArgumentException` → `ecr_invalid_argument` | `EcrInvalidArgument` → `ecr_invalid_argument` | `EcrArgumentError` / typed failure before send |

A Kotlin data class validates once at construction; a Swift struct stays
assignable afterwards, so an initialiser check there would be an assurance rather
than a guarantee. The iOS SDK checks the key at the last moment instead, and
exposes `EcrConfig.secureHashKeyError` for a caller that wants to ask first.

**From Dart the hosts agree**: `EcrConfig` refuses a bad key at construction,
before any call is made, so no host is ever handed one. And on every platform, a
key that cannot be used means nothing is sent — never traffic sent unsigned.

### 6.3 Diagnostics

| | Android | iOS | Windows |
|---|---|---|---|
| Log output | Logcat, tag `AmwalEcr` | Unified log, subsystem `com.amwalpay.ecr` | Flutter / Dart console (pure-Dart host) |
| On by default | debug builds only | debug builds only | debug builds only |
| Turned on afterwards | `adb shell setprop log.tag.AmwalEcr DEBUG` | Console.app, enabling the subsystem | run a debug build / attach the IDE debugger |

Mobile SDKs take an `EcrLogger` and neither has a logging dependency of its own;
each host routes it to the platform's log. The Windows host logs from Dart.
Messages may carry request and response payloads including the masked card
number, which is why they are off in release — they are transaction records.
A signed message's `secureHash` may appear; the key never does.

Nothing in the API depends on any of them.

---

### 6.4 What an interrupted app-to-app round trip means

Two answers look alike from the till's side and mean opposite things:

- **Response code `17`** — the cardholder pressed Cancel *inside* the payment
  app. The answer arrived and is signed. The outcome is known: nothing was
  taken. This is an `EcrDeclined`.
- **No answer at all** — the payment app was destroyed before it could answer
  (force-stopped, the device restarted, Android reclaimed it). This is an
  `EcrFailed` whose `outcomeIsUnknown` is set and whose `nextStep` is
  `inquireByMerchantReference`. **The money may have moved.** Inquire; never
  retry the sale.

This is why a `merchantReference` is not optional on this transport in
practice: it is the only handle that survives the round trip being cut, and
without one there is nothing to inquire by.

`cancel(operationId)` stops the till waiting and reports `EcrCancelled`, which
is also an unknown outcome. It cannot dismiss the payment app's screen — there
is no "never mind" intent, the cardholder may be mid-PIN, and one app cannot
finish another's Activity.

### 6.5 `autoInquireOnFailure` and the payment app

`EcrConfig.autoInquireOnFailure` defaults to on: a money-moving request that
fails is followed by an inquiry, so an unknown outcome is settled without the
caller doing anything. Over `appToApp` that inquiry is itself a round trip
through the payment app, which would put it back on screen moments after the
operator dismissed it.

So it is forced off for this transport, whatever the caller asked for, and the
recovery is the till's: read `outcomeIsUnknown`, and inquire by merchant
reference when the operator is ready. This is the one place where the setting
a caller passes is not the setting that is used, which is why it is written
down here rather than left in a comment.

---

## 7. Additions this wrapper makes

Two failure kinds have no counterpart in the native SDKs. They are the
wrapper's, and they are named as such in the contract:

| | Why it exists |
|---|---|
| `EcrCancelled` | The native SDKs have no cancellation. This is the wrapper's, and it carries the same "outcome unknown" weight as a timeout. |
| `EcrUnsupported` | The answer to "what happens where the platforms differ": a transport with no listener, a host that is not registered. Raised before anything is sent, so `outcomeIsUnknown` is `false`. |

`EcrUnauthenticated` is **not** in this list: it is the native SDKs' own
`Failure.Unauthenticated` / `EcrFailure.unauthenticated`, reported identically by
the mobile hosts and by the Windows Dart engine.

One reading is the wrapper's own: `EcrFailed.outcomeIsUnknown` is `false` once
`settled` is set — the follow-up found the transaction, so the delivery failed
but the outcome is known. The native SDKs report `recovered` and leave the
conclusion to the caller; this package draws it once, in the place every till
would otherwise draw it for itself.

A failure kind a **future** host reports that this build has never heard of is
read as `EcrMalformed` with `outcomeIsUnknown` set — the safe reading — rather
than as a decline.

---

## 8. Keeping this honest

Every claim above is covered by a test that runs on each release, in Dart,
Kotlin and Swift alike (Windows behaviour is covered by the Dart suite against
the pure-Dart host):

- the three channel contracts agree, literal for literal;
- amounts round identically on both mobile platforms and in Dart;
- an answer from the terminal is read identically;
- a request is sent once and answered once, including cancellation and a reply
  that arrives late;
- references, signing and the automatic follow-up behave the same;
- both native SDKs sign a payload to the same bytes, against a frozen digest;
- the bridge compiles against the *published* shape of the iOS SDK, so a type
  that is not exported publicly fails before it can reach an integrator;
- and the whole path runs on a device against a real terminal.
