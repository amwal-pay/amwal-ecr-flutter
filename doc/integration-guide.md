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
and an `ecrMode` of `1` (ethernet) or `2` (wi-fi). A terminal in any other state
does not listen on port 9100, and connections are refused. If `isReachable()`
answers `false` on an address you are sure of, check the profile before
debugging the network.

**2. The phone can route to the terminal.** Same subnet, or a network that
routes between them. A guest wi-fi with client isolation will not.

**3. You have the terminal's serial number.** The operator registered it; the
terminal shows its own address and port under the card scheme logos when the
link is wi-fi.

---

## Setting up

```dart
import 'package:amwal_ecr/amwal_ecr.dart';

final EcrTerminal terminal = EcrTerminal(
  host: '192.168.1.50',
  serialNumber: 'P653200085189',
  transport: EcrTransport.wifi,
  config: EcrConfig(
    ecrId: 'TILL7',          // how this till appears on the terminal's records
    currencyCode: '512',     // ISO 4217 numeric; 512 is OMR
    minorUnitDigits: 3,      // 3 for OMR, 2 for USD, 0 for JPY
  ),
);
```

An `EcrTerminal` holds no connection between calls, so it is cheap to build and
safe to keep. Build a new one when the settings change rather than mutating one.

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
  prefer the typed fields, which are the same on both platforms.

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

- Every call is safe from the UI isolate. The socket work happens on a native
  background thread on both platforms.
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

The repository ships a stand-in listener that speaks the same protocol:

```bash
python3 tools/fake_pos_server.py --port 9100                # approves
python3 tools/fake_pos_server.py --port 9100 --decline 51   # declines
python3 tools/fake_pos_server.py --port 9100 --delay 130    # forces a timeout
python3 tools/fake_pos_server.py --port 9100 --not-found    # inquiry misses
```

Point the example app, or your own till, at the machine running it.

In unit tests, replace the platform rather than the network:

```dart
final class FakeEcrPlatform extends AmwalEcrPlatform {
  @override
  Future<EcrResult> sale(EcrRequest request) async => const EcrFailed(
        merchantReferenceId: '',
        failure: EcrTimeout('no answer'),
      );
  // … the rest of the interface
}

AmwalEcrPlatform.instance = FakeEcrPlatform();
```

`example/test/widget_test.dart` does exactly this, and the case it spends most
of its effort on is the one you cannot arrange on real hardware on demand: a
payment whose outcome nobody knows.

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
