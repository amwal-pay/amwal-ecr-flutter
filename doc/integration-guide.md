# Integration guide

Putting `amwal_ecr` into a till. If you only read one section, read
[The one rule](#the-one-rule).

For what actually goes over the socket, see
[the protocol document](https://github.com/amwal-pay/ECR-simulator/blob/main/ecr-sdk/docs/protocol.md). You do not need it
to use this package.

---

## Before anything works

Three things have to be true, and two of them are not in your code.

**1. The terminal is in ECR mode.** Its TMS profile carries `terminalMode` `1`
and an `ecrMode` of `1` (USB cable, **Android only**), `2` (wi‑fi), `4` (Web
Service), or `5` (app to app, **Android only**). A terminal in wi‑fi mode
listens on port 9100; USB cable has no IP; app to app has no address at all,
because the terminal is the device your till is running on. On Windows and
iOS, USB cable and app to app are typed unsupported — use wi‑fi or Web
Service. If `isReachable()` answers `false` on an address you are sure of,
check the profile before debugging the network.

**2. The till can route to the terminal.** Same subnet, or a network that
routes between them. A guest wi-fi with client isolation will not. On Windows,
allow the app through the firewall for outbound TCP (and HTTPS for Web
Service). Nothing to check for app to app: there is no network in it.

**3. You have the terminal's serial number.** The operator registered it; the
terminal shows its own address and port under the card scheme logos when the
link is wi-fi.

---

## Setting up

```dart
import 'package:amwal_ecr/amwal_ecr.dart';

final EcrOpenedSession session = EcrSessions.open(
  host: '192.168.1.50',
  serialNumber: 'P653200085189',
  transport: EcrTransport.wifi,
  config: EcrConfig(
    ecrId: 'TILL7',          // how this till appears on the terminal's records
    currencyCode: '512',     // ISO 4217 numeric; 512 is OMR
    minorUnitDigits: 3,      // 3 for OMR, 2 for USD, 0 for JPY
  ),
);
final EcrTerminal terminal = session.terminal;
```

Prefer `EcrSessions.open` so sale, inquiry, and receipt share one transport.
An `EcrTerminal` holds no connection between calls, so it is cheap to build and
safe to keep. Build a new one when the settings change rather than mutating one.

### Driving the payment app on this same device

When your till runs on the terminal itself, there is no address to give: the
transaction is handed to the Amwal payment app installed beside you, and it
answers when the cardholder is done.

Every snippet below is from the example app, which is a working till you can
install on a terminal and read alongside this.

**1. Nothing to add to your manifest.** The package declares the payment app in
`<queries>`, and that reaches your app through the manifest merge. Without it,
from Android 11, resolving the payment app returns null and starting it throws
— which reads as "not installed" on a device where it plainly is.

**2. Offer the mode where you register a terminal.** Its `ecrMode` is 5, and it
is the one mode with no address to collect:

```dart
// lib/data/ecr_mode.dart
enum EcrMode {
  usbCable(1, 'USB Cable'),
  wifi(2, 'Wi‑Fi'),
  bluetooth(3, 'Bluetooth'),
  webService(4, 'Web Service'),
  appToApp(5, 'App to app');
  // …
  bool get isAppToApp => this == EcrMode.appToApp;
}
```

The registration screen hides the IP and port fields for it, and asks for
nothing in their place — which application takes the payment is not a setting:

```dart
// lib/ui/terminals/terminal_edit_screen.dart
if (_mode.isAppToApp) ...<Widget>[
  Text(
    'The terminal is this device. There is nothing to address: the '
    'transaction is handed to the Amwal payment app '
    '(${EcrPaymentApp.packageName}), and the serial number still has to be '
    'the one that app drives.',
  ),
],
```

The serial number still matters. It travels in the envelope exactly as it does
over a socket, and it has to be the terminal the payment app is provisioned as.

**3. Open the terminal.** One line differs from Wi‑Fi — and on the mode where
`host` would be an address, it is the payment app's application id:

```dart
// lib/ui/transaction/transaction_controller.dart
EcrTerminal _terminalFor(Terminal terminal, SelectedTerminalConfig active) {
  final EcrTransport transport = switch (terminal.mode) {
    EcrMode.usbCable => EcrTransport.usbCable,
    EcrMode.wifi => EcrTransport.wifi,
    EcrMode.bluetooth => EcrTransport.bluetooth,
    EcrMode.webService => EcrTransport.webService,
    EcrMode.appToApp => EcrTransport.appToApp,
  };

  return EcrSessions.open(
    host: switch (terminal.mode) {
      EcrMode.wifi => terminal.ipAddress,
      EcrMode.appToApp => EcrPaymentApp.packageName,
      _ => '',
    },
    serialNumber: terminal.serialNumber,
    transport: transport,
    config: active.ecrConfig,
  ).terminal;
}
```

`EcrTerminal.appToApp(serialNumber: …)` is the shorter way to say the same
thing when your till drives only this mode.

**4. Check it before you take an amount, if you like.** The probe launches
nothing — it asks whether the payment app is installed and will accept a
request:

```dart
if (active.usesLocalTerminal) {
  final EcrReachability probe = await terminal.probeReachability();
  if (!probe.reachable) {
    // Show why. Over app to app the example lists: the app is installed, it
    // is a build that accepts app-to-app requests, the merchant is signed in,
    // and the serial matches the terminal it drives.
    return;
  }
}
```

It cannot tell you whether a merchant is signed in. That answer only comes
back from a real request, which is the next step.

**5. Run the transaction.** Identical to every other transport:

```dart
final EcrResult result = await terminal.sale(
  EcrAmount.parse('10.500'),
  merchantReference: 'ORDER-91',
);
```

The payment app comes to the front, takes the card, and steps back when the
operator is done with the receipt. Your till returns to the foreground with
the answer already in hand.

**6. Read the answer.** Also identical — `EcrApproved`, `EcrDeclined`,
`EcrFailed` — with three things worth knowing before you ship it.

**Always send a `merchantReference`.** Your till and the payment app are two
apps, and Android can destroy either at any moment. If that happens mid-payment
you get no answer at all, and the reference is the only handle left to ask what
became of the transaction:

```dart
if (result.outcomeIsUnknown) {
  final EcrInquiry settled = await terminal.inquireByReference('ORDER-91');
  // EcrInquiryFound → the transaction happened; read transaction.status.
  // EcrInquiryNotFound → no record of it. Do not treat this as "it failed".
}
```

**Android only.** On iOS and on the web the operation is refused before
anything is sent, as an `EcrUnsupported` failure whose outcome is *not*
unknown — nothing was attempted.

**The merchant has to be signed in on the payment app.** If nobody is, the
request is refused immediately with a reason saying so, and no payment screen
is put in front of the operator. Show that reason: opening the Amwal app once
and signing in is the whole fix.

The payment app must also be visible to yours. The plugin declares it in
`<queries>`, so you get that from the manifest merge — but if you see "not
installed" on a device where it plainly is, that declaration is the first thing
to check.

### `minorUnitDigits` is the setting to get right

Amounts travel as a whole number of the currency's smallest unit. `1.234` at
three digits goes out as `000000001234`. Nothing cross-checks the digits against
`currencyCode`: set it to `2` for OMR and every amount is off by a factor of
ten, and neither side will object.

---

## The one rule

**A response that never arrives is not a decline.**

The card flow at the terminal does not depend on the socket staying up. If the
socket times out, the terminal may have taken the money and been unable to say
so. There is exactly one correct response, and it is not to try again:

```dart
final EcrResult result = await terminal.sale(amount);

if (result.outcomeIsUnknown) {
  await reconcile(receiptNumber);
  return;
}
```

```dart
Future<void> reconcile(String receiptNumber) async {
  // An inquiry authorises nothing and changes nothing, so it is safe to send —
  // and the terminal answers it even while it is taking a payment.
  final EcrInquiry inquiry = await terminal.inquire(
    receiptNumber: receiptNumber,
    transactionDate: today(),
  );

  switch (inquiry) {
    case EcrInquiryFound(:final EcrTransaction transaction):
      // Found is not paid. The status is what happened.
      if (transaction.status.toLowerCase() == 'approved') {
        bookAsPaid(transaction);
      } else {
        bookAsNotPaid(transaction);
      }
    case EcrInquiryNotFound():
      // Nothing was recorded, so nothing happened. Safe to take the payment
      // again — this is the only path on which that is true.
      break;
    case EcrInquiryFailed():
      // Still nothing learned. Leave it open and ask again; do not take a
      // second payment on a guess.
      break;
  }
}
```

`outcomeIsUnknown` is `true` for:

- every `EcrTimeout`, `EcrConnectionLost`, `EcrMalformed` and `EcrCancelled`;
- a decline carrying response code `91`, which is the terminal saying it could
  not tell you either.

It is `false` for `EcrUnreachable` and `EcrUnsupported` — nothing was sent — and
for every ordinary approval or decline.

**Nothing in this package retries.** Not on a timeout, not on a lost connection,
not on a host error. There is no configuration that turns retrying on, because
there is no failure worth charging a customer twice for.

---

## The operations

### Sale

```dart
final EcrAmount? amount = EcrAmount.tryParse(controller.text);
if (amount == null) {
  showError('Enter a plain decimal, e.g. 1.234');
  return;
}

final EcrResult result = await terminal.sale(amount);
```

The call takes as long as the cardholder takes: presenting a card, entering a
PIN, the backend authorising. Ninety seconds is not unusual, and the default
read timeout is 120 seconds for that reason. Show a spinner, not a countdown.

### Void

Cancels an earlier transaction **in full**. No amount — a void returns exactly
what the original took, and only the terminal knows that figure. No card
either: for a transaction taken on the same terminal it completes in about a
second.

```dart
final EcrResult result = await terminal.voidTransaction('215');
```

Add `originalTerminalId` for a transaction taken on a different terminal. That
route asks the backend and reads the card again, so it is neither instant nor
card-free.

A void is refused for three reasons, all of them before anything reaches the
backend: the original was not found, it is outside the void window configured in
TMS, or the backend says it cannot be voided. All three arrive as `EcrDeclined`,
and no money moved.

### Refund

```dart
final EcrResult result = await terminal.refund(
  EcrAmount.parse('0.216'),
  receiptNumber: '208',
  transactionDate: '20260809',   // yyyyMMdd — a receipt number is only
);                               // unique within a terminal's day
```

The cardholder presents their card to receive the money. Whether the refund is
allowed, and for how much, is the backend's decision.

### Inquiry

```dart
switch (await terminal.inquire(
  receiptNumber: '208',
  transactionDate: '20260809',
)) {
  case EcrInquiryFound(:final EcrTransaction transaction):
    print('${transaction.status} — ${transaction.amount} ${transaction.currency}');
  case EcrInquiryNotFound(:final String reason):
    print(reason);
  case EcrInquiryFailed(:final EcrFailure failure):
    print(failure.message);   // safe to try again
}
```

`transaction.canVoid` and `canRefund` have already had the void window and the
backend's rules applied, so a till can enable its buttons from them rather than
guessing:

```dart
voidButton.enabled = transaction.canVoid;
refundButton.enabled = transaction.canRefund && !transaction.isRefunded;
```

### Receipt

```dart
switch (await terminal.receipt(
  receiptNumber: '215',
  transactionDate: '20260809',
)) {
  case EcrReceiptReady(:final String url):
    showQrCode(url);    // the customer scans it and reads it on their phone
  case EcrReceiptUnavailable(:final String reason):
    showMessage(reason);
  case EcrReceiptFailed(:final EcrFailure failure):
    showMessage(failure.message);
}
```

Non-financial and reprintable — ask as often as you like, including while the
terminal is busy. A till with no printer can still hand a receipt over.

---

## Reading the answer

```dart
switch (result) {
  case EcrApproved(
      :final String amount,
      :final String rrn,
      :final String authCode,
      :final bool partialApproval,
      :final String requestedAmount,
    ):
    if (partialApproval) {
      // An APPROVAL, not a refusal. The bank authorised less than was asked
      // for; the goods go out once the difference is collected by other means.
      collectRemainder(requestedAmount, taken: amount);
    }
    printReceipt(amount: amount, rrn: rrn, authCode: authCode);

  case EcrDeclined(:final String responseCode, :final String reason)
      when result.outcomeIsUnknown:
    // Response code 91. Not a decision.
    await reconcile(receiptNumber);

  case EcrDeclined(:final String reason):
    showToCashier(reason);

  case EcrFailed() when result.outcomeIsUnknown:
    await reconcile(receiptNumber);

  case EcrFailed(:final EcrFailure failure):
    showToCashier(failure.message);   // nothing happened; safe to try again
}
```

Three things a till gets wrong if it is not careful:

- **A void has no authorisation code of its own.** It reverses one. The terminal
  returns a placeholder, so leave `authCode` off a void's receipt — printing it
  reads as an approval that never took place.
- **A partial approval is an approval.** Booking it as a decline loses money;
  booking it as a full sale loses more.
- **`raw` is there for anything not surfaced.** It is the terminal's whole answer
  as JSON text — parse it if you need a field this API does not model, but
  prefer the typed fields, which are the same on Android, iOS, and Windows.

---

## Cancelling

A till that has told the cardholder to present their card needs a way out of it.

```dart
final EcrOperation<EcrResult> sale = terminal.startSale(amount);

cancelButton.onPressed = () async {
  final bool wasRunning = await sale.cancel();
  // false means it had already finished — its real outcome is on sale.result,
  // and nothing was interrupted.
};

final EcrResult result = await sale.result;
```

**Say what it does.** "Cancel" reads as "the payment did not happen", and that
is not what it means. It stops the till waiting; the terminal is not told and
does not stop. The example app labels the button *Stop waiting* and says so
underneath — copy that, or something like it.

A cancelled money-moving request has an unknown outcome. Reconcile it exactly
like a timeout.

Cancelling an inquiry or a receipt is harmless: nothing changes either way.

Over app to app it means less still: the payment app is on screen in front of
the cardholder, and one app cannot dismiss another's screen. The till stops
waiting; the payment continues.

---

## Errors that are not outcomes

`EcrArgumentError` is thrown — not returned — when the call itself cannot be
made: a refund with no receipt number, a date that is not `yyyyMMdd`, a void
given an amount. Nothing was sent, so there is nothing to reconcile, and an
exception is the honest shape.

```dart
try {
  await terminal.refund(amount, receiptNumber: '', transactionDate: '20260809');
} on EcrArgumentError catch (error) {
  showFormError(error.message);   // a bug in the till, or a blank field
}
```

Everything that happens once a request is on its way comes back as a result,
never as an exception.

---

## Threading, lifecycles and concurrency

- Every call is safe from the UI isolate. Socket / HTTP work runs off the UI
  isolate (native background thread on Android and iOS; Dart `dart:io` on
  Windows).
- One terminal serves **one transaction at a time**. A second money-moving
  request while one is running comes back as `EcrDeclined` with response code
  `96` — nothing was attempted, and it is safe to send again once the terminal
  is free. Better still, disable the buttons while one is in flight; the example
  app does.
- An inquiry or a receipt is answered even while the terminal is busy.
- If the Flutter engine is detached while an operation is in flight, the
  operation is cancelled and its future never completes — there is nobody left
  to answer. The terminal may still finish what it was given, so a till that
  can be killed mid-sale should record the receipt number *before* sending and
  reconcile on next launch.

---

## Testing without hardware

A stand-in listener that speaks the same protocol is published alongside the
native SDK:

```bash
curl -O https://raw.githubusercontent.com/amwal-pay/ECR-simulator/main/tools/fake_pos_server.py

python3 fake_pos_server.py --port 9100                # approves
python3 fake_pos_server.py --port 9100 --decline 51   # declines
python3 fake_pos_server.py --port 9100 --delay 130    # forces a timeout
python3 fake_pos_server.py --port 9100 --not-found    # inquiry misses
```

Point the example app, or your own till, at the machine running it.

In unit tests, replace the platform rather than the network:

```dart
final class FakeEcrPlatform extends AmwalEcrPlatform {
  @override
  Future<EcrResult> sale(EcrRequest request) async => const EcrFailed(
        merchantReference: '',
        failure: EcrTimeout('no answer'),
      );
  // … the rest of the interface
}

AmwalEcrPlatform.instance = FakeEcrPlatform();
```

The example app's tests do exactly this, and the case worth spending your own
effort on is the one you cannot arrange on real hardware on demand: a payment
whose outcome nobody knows.

Use a placeholder signing key in tests, never a real Amwal one, and keep real
keys out of the repository entirely.

---

## A checklist before going live

- [ ] `minorUnitDigits` matches the currency.
- [ ] `ecrId` identifies this till, and is distinct from every other till on the
      merchant.
- [ ] The unknown-outcome path is implemented, and reachable — try it against
      `--delay 130`.
- [ ] There is no Retry button on an unknown outcome. Anywhere.
- [ ] A partial approval is booked as an approval.
- [ ] `authCode` is off the receipt for a void.
- [ ] Buttons are disabled while an operation is in flight.
- [ ] The Cancel button's wording does not promise that the payment was undone.
- [ ] The receipt number is recorded before a sale is sent, so a till killed
      mid-transaction can reconcile on next launch.
- [ ] On Windows, use Wi‑Fi or Web Service only (USB cable and app to app are
      Android-only), and confirm the PC can route to the terminal / Hub.
