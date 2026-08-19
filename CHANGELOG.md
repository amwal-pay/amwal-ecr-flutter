# Changelog

All notable changes to `amwal_ecr`. This project follows semantic versioning,
with the addition described in [the release policy](doc/release-policy.md): any
change to the platform-channel contract is breaking, and any change to what an
outcome *means* is breaking, however small the diff.

## 0.2.0

Brings the package level with `com.amwal-pay:ecr-sdk` 1.0.4 and `AmwalECR` 0.2.0
— the same three features on both platforms, over the same channel contract.

**Breaking.** The protocol renamed the field that names a transaction, so
`requestId` is `merchantReferenceId` everywhere: on `EcrResult`, `EcrInquiry`,
`EcrReceipt` and on the platform channel. Rename it at the call sites; the type
is unchanged and it still arrives filled in whether or not you supply one. The
channel contract changed too, so the Dart side and the native hosts must be
upgraded together — an old host does not lose a field, it stops being understood.

### Added

- **A reference the till chooses.** `merchantReferenceId` on `sale`,
  `voidTransaction`, `refund`, `run`, `inquire` and `receipt` — an order number,
  a basket id, whatever already names the sale in your system. Pass it and the
  same string identifies the transaction in your books, in the terminal's records
  and in any later lookup; leave it out and the host generates one. Either way it
  comes back on `EcrResult.merchantReferenceId`, and it is the only handle you
  hold if the answer never arrives.
- **`EcrTerminal.inquireByReference`.** The answer to an outcome you never
  received: looks a transaction up by the reference it was sent with, rather than
  by a receipt number that only arrives *in* the answer.
- **`EcrFailed.recovered`, `.recoveredTransaction` and `.settled`.** The host now
  follows a lost money-moving request with one inquiry and attaches what it
  found. A `settled` failure is a delivery that failed and an outcome that is
  *known*, so `outcomeIsUnknown` is false and the till books the transaction
  instead of reconciling it. Turn the follow-up off with
  `EcrConfig.autoInquireOnFailure`. Nothing is ever re-sent.
- **`EcrConfig.secureHashKey`.** The secret this till shares with the terminal.
  Set it and the native SDK signs every request and checks every answer. Refused
  at construction if it is not an even-length hex string of at least 16
  characters — on the shop floor a bad key is a decline the cashier cannot
  explain. Required in practice: a terminal refuses what it cannot verify. The
  key is never printed by `toString`.
- **`EcrUnauthenticated`**, for an answer that cannot be shown to have come from
  the terminal. Leaves the outcome **unknown**, like a timeout — never a decline,
  and never to be retried.
- **`EcrNextStep`**, on every `EcrResult`. What the terminal says to do about an
  outcome, rather than something a till has to infer from a response code. A
  decline that asks for an inquiry now reports `outcomeIsUnknown`.

### Changed

- Config, arguments and results carry the new fields across the channel:
  `secureHashKey`, `autoInquireOnFailure`, `merchantReferenceId`,
  `originalMerchantReference`, `nextStep`, `recovered`, and the
  `unauthenticated` failure kind. The frozen contract test lists them all.
- A reference the wire format cannot carry — over 32 characters, or containing a
  space, `&` or `=` — throws `EcrArgumentError` before anything is sent, on both
  platforms and in Dart, with the same message.
- The Android host now requires `com.amwal-pay:ecr-sdk:1.0.4`, and the iOS host
  `AmwalECR ~> 0.2.0`.

## 0.1.0

First release.

### Added

- **One Dart API over both platforms.** `EcrTerminal` with `isReachable`,
  `sale`, `voidTransaction`, `refund`, `inquire` and `receipt`, plus a `run`
  form for a till driving the operation from its own menu.
- **Typed outcomes.** Sealed `EcrResult` (`EcrApproved` / `EcrDeclined` /
  `EcrFailed`), `EcrInquiry` and `EcrReceipt`, each with its own branches, so an
  inquiry that failed cannot be mistaken for a sale that was refused.
- **`outcomeIsUnknown` on every result.** Set for timeouts, lost connections,
  unreadable answers, cancellations, and a decline carrying response code `91`.
  Nothing in the package retries a money-moving request, and this is the flag
  that tells a caller not to either.
- **Exact amounts.** `EcrAmount` holds a decimal, never a `double`, and converts
  to the wire's minor units once — in the native host, with half-up rounding, so
  the two platforms cannot disagree about a rounding boundary.
- **Cancellable operations.** The `start…` methods return an `EcrOperation` with
  a `cancel()`, which answers the caller at once with `EcrCancelled`. Cancelling
  does not stop the terminal, and the outcome is unknown — documented as such
  everywhere it appears.
- **Transport awareness.** `EcrTransport` mirrors the TMS profile's `ecrMode`.
  `bluetooth` and `webService` answer with a typed `EcrUnsupported` failure
  without opening a socket, identically on both platforms.
- **Android host** bridging to `com.amwal-pay:ecr-sdk` **1.0.3**, pinned.
- **iOS host** bridging to `AmwalECR` **`~> 0.1.0`**, from CocoaPods trunk or
  Swift Package Manager. Both hosts are bridges: no wire protocol lives in this
  package, and a native module in the same app can drive the same terminal
  through the same SDK without Flutter.
- **Both CocoaPods and Swift Package Manager** on iOS, from the same sources —
  `ios/amwal_ecr.podspec` and `ios/amwal_ecr/Package.swift`, naming the same
  dependency range.
- **Contract tests on all three sides.** Every method name, argument key, result
  key, outcome, failure kind and error code is asserted against frozen literals
  in Dart, Kotlin and Swift — the only thing keeping three hand-written copies
  of the same document in step.
- **An example till** demonstrating every operation, and in particular an
  outcome card that offers *Ask the terminal* and never *Retry* when the outcome
  is unknown.

### Compatibility

| | |
|---|---|
| Dart | `^3.5.0` |
| Flutter | `>=3.22.0` |
| Android | API 21+, `com.amwal-pay:ecr-sdk:1.0.3` |
| iOS | 12.0+, Swift 5.5, `AmwalECR ~> 0.1.0` |
| ECR protocol | version `1` |
