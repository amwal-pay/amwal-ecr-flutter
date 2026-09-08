# amwal_ecr

Drive an Amwal POS terminal from Flutter, on Android and iOS, through one Dart
API.

```dart
final EcrTerminal terminal = EcrTerminal(
  host: '192.168.1.50',
  serialNumber: 'P653200085189',
);

switch (await terminal.sale(EcrAmount.parse('1.234'))) {
  case EcrApproved(:final String amount, :final String rrn):
    print('Took $amount, RRN $rrn');
  case EcrDeclined(:final String reason):
    print('Refused: $reason');
  case EcrFailed(:final EcrFailure failure):
    print('No answer: ${failure.message}');
}
```

Sale, void, refund, inquiry and e-receipt, with the same types, the same units
and the same outcomes on both platforms.

---

## The one rule

**A response that never arrives is not a decline.**

If the socket times out or the connection breaks, the terminal may have
completed the payment and been unable to say so. Treating that as a refusal and
sending the request again is how a customer gets charged twice.

Nothing in this package retries a money-moving request — not on a timeout, not
on a lost connection, not on a host error. Neither should you:

```dart
final EcrResult result = await terminal.sale(
  amount,
  merchantReference: order.number,   // your own name for this sale
);

if (result.outcomeIsUnknown) {
  // Do not retry. Ask the terminal what happened, quoting the reference you
  // sent — a receipt number arrives *in* the answer, which is what went missing.
  switch (await terminal.inquireByReference(order.number)) {
    case EcrInquiryFound(:final EcrTransaction transaction):
      reconcile(transaction);
    case EcrInquiryNotFound():
      // Nothing was taken. Only now is it safe to send the sale again.
    case EcrInquiryFailed():
      // Still unknown. Ask again later; do not retry the sale.
  }
  return;
}
```

Most of the time the package has already asked for you: a money-moving request
whose answer never arrived is followed by one inquiry, and what it found is on
`EcrFailed.recovered`. When `settled` is set the delivery failed but the outcome
is *known*, and `outcomeIsUnknown` is `false`:

```dart
if (result case EcrFailed(:final EcrTransaction? recoveredTransaction)
    when result.settled) {
  // The exchange failed, but the terminal has since said what became of it.
  book(recoveredTransaction!);
}
```

`outcomeIsUnknown` is set for every timeout, every lost connection, every
unreadable answer, every cancellation, every answer that could not be shown to
have come from the terminal — and for a decline carrying response code `91` or
asking to be inquired about, which is the terminal saying it could not tell you
either.

---

## Install

```yaml
dependencies:
  amwal_ecr: ^0.2.0
```

The native SDKs come with it: `com.amwal-pay:ecr-sdk` from Maven Central on
Android, and `AmwalECR` from CocoaPods trunk — or Swift Package Manager, if the
project is built with `flutter config --enable-swift-package-manager` — on iOS.
Both are published SDKs in their own right, so a native module in the same app
can use the same terminal without going through Flutter.

The Android host declares `INTERNET` itself. On iOS, add the local network
description to `ios/Runner/Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Connects to the payment terminal to take card payments.</string>
```

iOS asks the user before an app may talk to devices on the local network, and a
refusal is indistinguishable from a terminal that is switched off: every call
answers `EcrUnreachable`. Ship the key, and treat a first-run `EcrUnreachable`
on iOS as a permission question before a networking one.

If the terminal is on a different subnet from the phone, that is a network
problem, not a configuration one — the two have to be able to route to each
other.

---

## Getting started

### 1. The terminal has to be in ECR mode

A terminal does not listen on port 9100 by default. Its TMS profile decides:
`terminalMode` `1` puts it in ECR mode, and `ecrMode` says how it is attached.
**The terminal opens a listener for `ecrMode` 2 (wi‑fi). `ecrMode` 1 is USB
cable (Android only, no IP). Web Service (`ecrMode` 4) uses REST.**

```dart
EcrTerminal(
  host: '192.168.1.50',
  serialNumber: 'P653200085189',
  transport: EcrTransport.wifi,   // ecrMode 2
);
```

On `bluetooth` every operation answers with an
[`EcrUnsupported`] failure immediately, without opening a socket — so a till
reading a profile it does not control handles it as one more outcome rather
than as a hang. USB cable is supported on Android; on iOS it returns the same
typed unsupported failure.

The terminal shows its own IP and port under the card scheme logos when the link
is wi-fi. That is what the operator reads off and registers.

### 2. Check it is listening

```dart
if (!await terminal.isReachable()) {
  // Wrong address, terminal off, or a different network.
  return;
}
```

Worth doing before a sale: it turns a wrong address into an immediate answer
rather than a failure a cardholder waits through. It proves the port is open,
not that the terminal is idle — a terminal already taking a payment answers a
handshake too.

### 3. Take a payment

```dart
final EcrResult result = await terminal.sale(EcrAmount.parse('1.234'));
```

The call takes as long as the cardholder takes. Ninety seconds is not unusual;
the default read timeout is 120 seconds for that reason.

---

## Operations

| | What it does | Needs |
|---|---|---|
| `sale(amount)` | Takes a payment. The cardholder presents their card. | amount |
| `voidTransaction(receiptNumber)` | Cancels an earlier transaction **in full**. No card, no amount — a void returns exactly what the original took. | receipt number |
| `refund(amount, …)` | Returns money against an earlier transaction, in full or in part. The cardholder presents their card. | amount, receipt number, the original's day |
| `inquire(…)` | Asks what became of an earlier transaction, by receipt number. Reads only. | receipt number, the original's day |
| `inquireByReference(…)` | The same question, by the reference *you* sent the transaction with. The lookup to use when an answer never arrived. | the original's reference |
| `receipt(…)` | Fetches the e-receipt as a URL, to show as a QR code. | receipt number, the original's day |
| `isReachable()` | Whether the port is open. | — |

Every money-moving call also takes `merchantReference`: your own name for the
transaction — an order number, a basket id. Pass it and the same string
identifies the sale in your books, in the terminal's records and in any later
lookup. Leave it out and one is generated; either way it comes back on
`EcrResult.merchantReference`, and it is the only handle you hold before the
terminal answers.

Every one of them has a `start…` twin — `startSale`, `startRefund`, … — that
returns an [`EcrOperation`] instead of a future, so a till can offer a Cancel
button while the cardholder has the terminal:

```dart
final EcrOperation<EcrResult> sale = terminal.startSale(amount);
cancelButton.onPressed = sale.cancel;

final EcrResult result = await sale.result;
```

**Cancelling does not undo a payment.** Closing the socket tells the terminal
nothing; a cardholder mid-PIN carries on. A cancelled sale is an unknown
outcome, exactly like a timeout.

### Inquiry is the safe one

An inquiry authorises nothing, presents no card and changes nothing, so it is
safe to repeat — and the terminal answers it **even while it is taking a
payment**. That is the point of it: after a timeout the outcome is unknown, and
this is how a till finds out instead of retrying.

```dart
switch (await terminal.inquire(
  receiptNumber: '215',
  transactionDate: '20260809',
)) {
  case EcrInquiryFound(:final EcrTransaction transaction):
    // Finding it is not the same as it having been paid.
    print('${transaction.status}: ${transaction.amount} ${transaction.currency}');
    print('Can void: ${transaction.canVoid}');   // already has the void
    print('Can refund: ${transaction.canRefund}'); // window applied
  case EcrInquiryNotFound(:final String reason):
    print(reason);
  case EcrInquiryFailed(:final EcrFailure failure):
    // Harmless — an inquiry changes nothing, so try again.
    print(failure.message);
}
```

---

## Amounts

Amounts are `EcrAmount`, never `double`. A binary float cannot hold 1.234, and
an amount off by a thousandth of a rial reconciles against nothing.

```dart
EcrAmount.parse('1.234');                            // from a text field
EcrAmount.tryParse(controller.text);                 // null while half-typed
EcrAmount.fromMinorUnits(1234, minorUnitDigits: 3);  // 1.234
```

The wire carries minor units — 1.234 OMR goes out as `000000001234` — and the
conversion happens once, in the native host, using `EcrConfig.minorUnitDigits`.
Set that to match your currency:

| Currency | `minorUnitDigits` |
|---|---|
| OMR — 1 rial = 1000 baisa | `3` (default) |
| USD, EUR, SAR | `2` |
| JPY | `0` |

**Nothing cross-checks it against `currencyCode`.** Getting it wrong sends every
amount off by a factor of ten and neither side will object.

Amounts come *back* as strings in major units (`'1.234'`) — the terminal's own
figure, reprinted rather than recomputed.

---

## Outcomes

```
EcrResult ── EcrApproved   money moved
          ├─ EcrDeclined   the terminal answered and refused
          └─ EcrFailed     no answer — see EcrFailure
```

| `EcrFailure` | Outcome known? | Means |
|---|---|---|
| `EcrUnreachable` | ✔ nothing happened | Nothing is listening |
| `EcrTimeout` | ✘ **unknown** | Accepted, never answered |
| `EcrMalformed` | ✘ **unknown** | Answered, illegibly |
| `EcrConnectionLost` | ✘ **unknown** | Broke part way through |
| `EcrUnauthenticated` | ✘ **unknown** | The answer could not be shown to have come from the terminal |
| `EcrCancelled` | ✘ **unknown** | You gave up waiting |
| `EcrUnsupported` | ✔ nothing happened | This platform cannot do it |

A partial approval is an **approval**: `EcrApproved.partialApproval` is set, and
`requestedAmount` says what was asked for. The goods go out once the difference
is collected by other means.

Response codes worth knowing (`EcrResponseCode`), all readable off `EcrDeclined`:

- `96` `isTerminalBusy` — a transaction is already running. Nothing was
  attempted; safe to send again once the terminal is free.
- `17` `isCancelledAtTerminal` — the operator or cardholder cancelled.
- `25` `isOriginalNotFound` — no such receipt number for that day.
- `91` — `outcomeIsUnknown` is `true`. The one decline that is not a decision.

A decline can also carry `nextStep`. It is normally `EcrNextStep.none` — a
decline says plainly that no money moved — but the terminal can report that it
does not actually know, and then `outcomeIsUnknown` is set and the answer is an
inquiry rather than a retry.

---

## Signing the link

A terminal refuses what it cannot verify, so in practice a till needs the secret
Amwal issues for it. **The app owns persistence** and passes **one** value on
`EcrConfig.secureHashKey` for the selected mode — LAN (Wi‑Fi / USB cable) and
Web Service use different secrets, but the plugin only consumes the field you
assign (see the example app's `secureHashKeyFor`):

```dart
// App-owned: pick the stored secret for this terminal mode
final String secret = settings.secureHashKeyFor(terminal.mode);

final EcrTerminal ecr = EcrTerminal(
  host: '192.168.1.50',
  serialNumber: 'P653200085189',
  config: EcrConfig(secureHashKey: secret),
);
```

Every request is then signed and every answer checked — both that it is signed
with this terminal's key, and that it answers *this* request. An answer that
fails either check is `EcrUnauthenticated`: the outcome is unknown, never a
decline, and never to be retried.

The key never belongs in source control or in an app bundle. It is not printed by
`EcrConfig.toString`, and a malformed one throws `EcrArgumentError` at
construction rather than becoming a decline the cashier cannot explain on the
shop floor.

---

## Documentation

- **[Integration guide](doc/integration-guide.md)** — the whole thing, with the
  patterns a till actually needs.
- **[Compatibility matrix](doc/compatibility-matrix.md)** — exact native
  versions, platform floors, and every place the two platforms differ.
- **[Changelog](CHANGELOG.md)** — what changed in each version, and what a
  version number promises.
- **[Wire protocol](https://github.com/amwal-pay/ECR-simulator/blob/main/ecr-sdk/docs/protocol.md)** — what actually goes over
  the socket, if you are debugging on the wire.

---

## The example app

`example/` is a direct port of the Android example in `app/`: the same two
screens, the same settings, the same order of checks, the same dialogs.

- **Terminals** — register POS terminals by ECR mode (Wi‑Fi, USB cable, or Web
  Service), with separate LAN and Web Service signing keys and environment
  (SIT/UAT/PROD), matching the Android simulator app.
- **Transaction** — type, amount, receipt number, the original's date, and which
  terminal. It probes the terminal before it sends anything, then shows the
  outcome in the same dialogs.

It is deliberately a plain till rather than a showcase: the package also offers
cancellation, transport selection and a standalone reachability probe, and the
example uses none of them — see
[response code 96](#a-sale-comes-back-96) for why that matters.

```bash
cd example
flutter run
```

**Android build fails with `25.0.2`?** Flutter is using JDK 25 from Android Studio,
which Android Gradle Plugin does not support yet. Use JDK 17:

```bash
flutter config --jdk-dir="$(/usr/libexec/java_home -v 17)"
```

Without hardware, run the stand-in listener that ships with the reference
implementation and point the app at the machine running it:

```bash
curl -O https://raw.githubusercontent.com/amwal-pay/ECR-simulator/main/tools/fake_pos_server.py

python3 fake_pos_server.py --port 9100
python3 fake_pos_server.py --port 9100 --decline 51
python3 fake_pos_server.py --port 9100 --delay 130   # a timeout
```

---

## Troubleshooting

### A sale comes back `96`

> Declined — A transaction is already in progress on this terminal

**This is the terminal's state, not an error in the package.** Nothing was
attempted, so nothing has to be reconciled.

Two things on the terminal produce it, and the second is almost always the one:

1. The terminal is already serving another ECR request. Cleared as soon as that
   one finishes.
2. **The terminal's own transaction screen is open.** The terminal refuses every
   money-moving request from the moment that screen opens until it is closed —
   while a card is being read, while a status screen is up, while a **receipt is
   still showing**, and for as long as anyone leaves it open. Neither a closed
   socket nor time clears it; only closing the screen does.

**Two ways to tell.** A terminal in this state never goes to its screen saver.
And an **inquiry still works**, because the terminal answers inquiries and
receipts whether or not it is busy. An inquiry that succeeds while a sale is
refused proves the network, the plugin and the protocol are all fine and the
terminal is simply occupied.

**To clear it:** on the terminal, close the transaction screen and get back to
the idle payment screen. If it looks idle and still refuses, restart the POS app
on the terminal.

**To avoid it:** send one request at a time and keep the buttons disabled until
it answers, as the example does. Do not offer a cancel unless the till genuinely
needs one — abandoning a request leaves the terminal working on it. If you do
offer one, treat a cancelled sale exactly like a timeout: `outcomeIsUnknown` is
set, and the next step is an inquiry, not a retry.

### Seeing what is actually sent

A debug build logs every call and every answer, the way the Android example
does. Nothing needs turning on:

```bash
adb logcat -s AmwalEcr          # Android
```

```
AmwalEcr: -> sale op=m1k2j3-1a2b host=192.168.1.50:9100 transport=wifi
AmwalEcr: Sending SALE 4F2A9C1B7E30 to 192.168.1.50:9100
AmwalEcr: {"version":1,"messageType":"SALE",...}
AmwalEcr: <- approved code=00
```

On iOS the same lines go to the Xcode console, prefixed `[AmwalEcr]`.

Read it in this order:

- **No `->` line at all** — the call never left Dart. The form was refused
  (`EcrArgumentError`), or no terminal is registered and the button is
  disabled. Nothing was sent.
- **`->` but no `Sending`** — the plugin refused it before the socket:
  a transport with no listener, or a missing argument. The `<-` line says which.
- **`Sending` but no `<-` for two minutes** — the terminal has the request and
  is waiting for the cardholder. That is the normal case for a sale.
- **`<- failed unreachable`** — nothing is listening. See below.

Release builds stay quiet. To make one talk for a session:
`adb shell setprop log.tag.AmwalEcr DEBUG`.

### Nothing answers at all

`isReachable()` returns `false`, or a sale fails with `EcrUnreachable`:

- the terminal's TMS profile must have `terminalMode` `1` and `ecrMode` `1` or
  `2` — on any other mode the port is simply not open;
- the terminal must be on its idle screen;
- the phone and the terminal must be able to route to each other. A guest
  network with client isolation will not work, and an **Android emulator cannot
  reach a device on your LAN** without port forwarding — use a real phone on the
  same Wi-Fi.

---

## Licence

Apache 2.0. See [LICENSE](LICENSE).
