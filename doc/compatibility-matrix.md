# Compatibility matrix

What this wrapper is built against, what it runs on, and every place the two
platforms are not the same.

Read the last section before shipping. "Equivalent on Android and iOS" is a
claim with exceptions, and they are written down here rather than discovered.

---

## 1. Versions

### This package

| | |
|---|---|
| `amwal_ecr` | 0.2.0 |
| Dart SDK | `^3.5.0` — the API uses sealed classes and pattern matching |
| Flutter | `>=3.22.0` |
| Protocol version | `1` (the `version` field in every request) |

The two native providers must be upgraded **together**. They speak the same wire
format, and the 1.0.4 / 0.2.0 line renamed the field naming a transaction from
`requestId` to `merchantReferenceId`; a host on the older line is not missing a
field, it fails to be understood by a current terminal.

### Native providers

| Platform | Provider | Version | Source |
|---|---|---|---|
| Android | `com.amwal-pay:ecr-sdk` | **1.0.4**, exact | Maven Central |
| iOS | `AmwalECR` | **`~> 0.2.0`** | [CocoaPods trunk](https://github.com/amwal-pay/AmwalECR-iOS-CocoaPods), and [SwiftPM](https://github.com/amwal-pay/AmwalECR-iOS-SPM) |

Both providers are published SDKs that native apps use directly, without
Flutter. This package is a bridge over them and holds no protocol code of its
own.

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

| Platform | Supported |
|---|---|
| Android | ✔ |
| iOS | ✔ |
| macOS, Windows, Linux, Web | ✘ — no host is registered, so every call answers `EcrUnsupported` |

A missing host is reported as `EcrUnsupported` with the message naming a
rebuild, rather than as a thrown `MissingPluginException`, so an app running on
an unsupported platform degrades instead of crashing.

---

## 3. Transports

`EcrTransport` mirrors the `ecrMode` a terminal's TMS profile carries.

| `EcrTransport` | `ecrMode` | Android | iOS | Behaviour |
|---|---|---|---|---|
| `ethernet` | 1 | ✔ | ✔ | TCP to the terminal |
| `wifi` | 2 | ✔ | ✔ | TCP to the terminal |
| `bluetooth` | 3 | ✘ | ✘ | `EcrUnsupported`, nothing sent |
| `webService` | 4 | ✘ | ✘ | `EcrUnsupported`, nothing sent |

The two unsupported transports are unsupported **identically on both
platforms**, and for the same reason: the terminal does not open its ECR
listener for them at all, so there is nothing to connect to. This is not a gap
in the wrapper.

A `EcrTransport` value the running build does not recognise reads as `null` from
`fromWireValue` rather than being guessed at — a profile carrying a future
`ecrMode` will not be treated as an IP transport by accident.

---

## 4. Operations

Every operation behaves identically on both platforms. This table exists so that
"identically" is a checkable claim rather than an assurance.

| Operation | Android | iOS | Notes |
|---|---|---|---|
| `isReachable` | ✔ | ✔ | Bounded by `probeTimeout` on both |
| `sale` | ✔ | ✔ | |
| `voidTransaction` | ✔ | ✔ | |
| `refund` | ✔ | ✔ | |
| `inquire` | ✔ | ✔ | Answered while the terminal is busy, on both |
| `inquireByReference` | ✔ | ✔ | The lookup after an answer goes missing |
| `receipt` | ✔ | ✔ | |
| `cancel` | ✔ | ✔ | Same observable behaviour; different mechanism — see §6 |

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
| `merchantReferenceId` | `String` | `String` — `''` means "generate one" | `String` | `String` |
| `secureHashKey` | `String` | `String` — `''` means unsigned | `String` | `String` |
| `nextStep` | `EcrNextStep` | `String`, the protocol's own name | `NextStep` | `EcrNextStep` |
| `recovered` | `EcrInquiry?` | an inquiry map, **absent** when none | `EcrInquiry?` | `EcrInquiry?` |

Three rules hold everywhere:

- **Amounts are never doubles.** They cross as decimal strings in major units,
  and are converted to the wire's minor units once, in the native host, with
  half-up rounding. `1.2345` at three decimal places is `1235` on both.
- **Timeouts cross as whole milliseconds**, because `Duration` and
  `TimeInterval` disagree about units and a key that does not name one invites a
  guess. Hence `connectTimeoutMs`, not `connectTimeout`.
- **A JSON `null` reads as an empty string**, never as the text `"null"`, on
  both hosts. Every field of `EcrTransaction` is non-nullable for that reason.
- **`recovered` is absent, not null, when no follow-up was made.** "Nothing was
  asked" and "the lookup found nothing" are different facts and a till acts on
  them differently, so they are not spelled the same way.

---

## 6. Where the platforms genuinely differ

Two differences exist. Neither is observable from Dart, and they are recorded
here because "not observable" is a thing that has to stay true. Diagnostics used
to be a third; §6.3 records what both platforms now do.

### 6.1 What a cancel does to the socket

| | Android | iOS |
|---|---|---|
| Answers the caller | immediately, `EcrCancelled` | immediately, `EcrCancelled` |
| The blocked read | keeps running until `responseTimeout`, then its answer is discarded | returns at once — the descriptor is `shutdown` |
| A thread is held | yes, until the read unwinds | no |

The Kotlin SDK does not expose its socket, so a cancelled coroutine cannot
interrupt a blocking read; the wrapper answers the caller at once and lets the
orphaned read finish on its own. The Swift implementation owns its socket and
shuts it down.

**Neither tells the terminal anything.** A cancelled money-moving request has an
unknown outcome on both platforms, and is reconciled by an inquiry, never
retried.

### 6.2 Where a malformed secret is caught

| | Android | iOS |
|---|---|---|
| Rejected by | `EcrConfig`'s constructor | `EcrMessage.build`, the last point before the key is used |
| Reported as | `IllegalArgumentException` → `ecr_invalid_argument` | `EcrInvalidArgument` → `ecr_invalid_argument` |

A Kotlin data class validates once at construction; a Swift struct stays
assignable afterwards, so an initialiser check there would be an assurance rather
than a guarantee. The iOS SDK checks the key at the last moment instead, and
exposes `EcrConfig.secureHashKeyError` for a caller that wants to ask first.

**From Dart the two are the same**: `EcrConfig` refuses a bad key at
construction, before any call is made, so neither host is ever handed one. And on
both, a key that cannot be used means nothing is sent — never traffic sent
unsigned.

### 6.3 Diagnostics

| | Android | iOS |
|---|---|---|
| SDK log output | Logcat, tag `AmwalEcr` | Unified log, subsystem `com.amwalpay.ecr` |
| On by default | debug builds only | debug builds only |
| Turned on afterwards | `adb shell setprop log.tag.AmwalEcr DEBUG` | Console.app, enabling the subsystem |

Both SDKs take an `EcrLogger` and neither has a logging dependency of its own;
each host routes it to the platform's log. The messages carry request and
response payloads including the masked card number, which is why they are off in
release — they are transaction records, and they are exactly what is needed when
a terminal is not answering. A signed message's `secureHash` appears in them too;
the key never does.

Nothing in the API depends on either.

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
both.

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

The claims above are tested, not asserted:

| Claim | Where |
|---|---|
| The three channel contracts agree | `test/platform/channel_contract_test.dart`, `EcrChannelContractTest.kt`, `EcrChannelContractTests.swift` — the same literals, written out by hand three times |
| Amounts round identically | `test/model/ecr_amount_test.dart`, the iOS SDK's `EcrDecimalTests.swift`, and the Android SDK's `AmountReportingTest.kt` |
| The answer is read identically | `test/platform/ecr_codec_test.dart`, the iOS SDK's `EcrResponseReaderTests.swift` — the same payloads |
| A request is sent once and answered once | `channel_completion_test.dart`, `EcrCallHandlerTest.kt`, `EcrCallHandlerTests.swift` |
| References, signing and the follow-up behave the same | `test/reference_and_signing_test.dart`, `EcrReferenceAndSigningTest.kt`, `EcrReferenceAndSigningTests.swift` — the same cases in the same words |
| The two SDKs sign identically | `SecureHashTest.kt` and `SecureHashTests.swift` — the same key, the same payloads, and a frozen HMAC digest on the iOS side |
| The bridge builds against the *published* shape of the iOS SDK | `tool/run_swift_tests.sh` — it compiles the bridge against `AmwalECR` as a package, so a type the SDK does not export publicly fails here |
| Cancellation and late replies | the same three files |
| The real socket, the real SDK | `example/integration_test/app_test.dart` |
