# Amwal ECR SDK for Flutter

`amwal_ecr` drives an Amwal POS terminal from a Flutter till on Android, iOS and Windows, through one Dart API: sale, void, refund, inquiry, e-receipt, close receipt, settlement, and sign-on — and, app to app, printing a receipt image on the terminal's printer. Wi-Fi uses the terminal's ECR port. USB uses the cable. App to app hands the request to the payment app on the same device. Web Service uses HTTPS to the Amwal Hub. Card data stays on the terminal.

Package `amwal_ecr` **0.5.0**. Open one session, call the operation, then read the result. Same types, same units and the same outcomes on every host that supports the transport; the [compatibility matrix](doc/compatibility-matrix.md) lists the few places Android, iOS and Windows differ.

## Install

- Flutter, Dart 3. Android, iOS 17 or later, Windows.
- Android uses `com.amwal-pay:ecr-sdk` **1.0.11** from Maven Central. iOS uses `AmwalECR` **0.3.0** from CocoaPods trunk, or Swift Package Manager with `flutter config --enable-swift-package-manager`. Windows has no native binary: a pure-Dart host speaks Wi-Fi TCP and Web Service HTTPS over `dart:io`.

```yaml
dependencies:
  amwal_ecr: 0.5.0
```

Pin the version. A channel change between the Dart side and the native host is a breaking release.

**iOS.** `AmwalECR` 0.3.0 requires iOS 17: raise the Runner deployment target. iOS asks the user before an app may talk to devices on the local network, and a refusal looks exactly like a terminal that is switched off — every call answers `EcrUnreachable`. Ship the description in `ios/Runner/Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Connects to the payment terminal to take card payments.</string>
```

**Android.** The plugin declares `INTERNET` itself. App to app needs the payment app declared in `<queries>`. See [App to app implementation](#app-to-app-implementation).

**Windows.** Allow the app through the firewall when prompted: outbound TCP to the terminal (port `9100`) and HTTPS to the Hub. Put the PC on a network that can route to the terminal; guest Wi-Fi with client isolation does not work. USB cable and app to app are not available on Windows (`EcrUnsupported`).

## Open a session

<a id="ecropenedsession"></a>

Open one session for the terminal and keep it. Every sale, void, refund, inquiry, e-receipt, close receipt, and settlement can use it. `EcrSessions.open` uses the same transport for all of them.

A terminal listens only when its TMS profile says so: `terminalMode` `1` is ECR, and `ecrMode` picks the link — `1` USB cable, `2` Wi-Fi, `4` Web Service, `5` app to app. Bluetooth (`3`) answers `EcrUnsupported` at once, without opening anything.

### Wi-Fi implementation

Each terminal shows its IP address and port on its idle screen, under the card logos. Use that address to reach it from the till. The port is 9100. The till and the terminal must be on the same Wi-Fi.

```dart
final EcrTerminal terminal = EcrSessions.open(
  host: '192.168.1.50',              // port defaults to 9100
  serialNumber: 'P653200085189',
  transport: EcrTransport.wifi,
  config: EcrConfig(secureHashKey: wifiKey),
).terminal;
```

### Web Service implementation

```dart
final EcrTerminal terminal = EcrSessions.open(
  host: '',                          // no address: the Hub routes to the terminal
  serialNumber: 'P653200008251',
  transport: EcrTransport.webService,
  config: EcrConfig(
    secureHashKey: webServiceKey,
    merchantId: '13593',
    terminalId: '101311',
    environment: EcrEnvironment.uat, // sit is the default; prod for live
  ),
).terminal;
```

Hub addresses stay inside the SDK. A Web Service operation waits 130 seconds by default (`EcrConfig.webServiceResponseTimeout`).

### USB cable implementation

Android only. The till is the USB host and the terminal is the accessory. The cable key is the Wi-Fi key. After the cable is open, the operations follow the same rules as Wi-Fi.

```dart
final EcrTerminal terminal = EcrSessions.open(
  host: '',                          // a cable has no address
  serialNumber: 'P653200085189',
  transport: EcrTransport.usbCable,
  config: EcrConfig(secureHashKey: wifiKey),
).terminal;
```

### App to app implementation

Android only. Use app to app when the till is installed on the terminal itself. There is no address: the payment app is `com.amwalpay.pos` (`EcrPaymentApp.packageName`). The key is the Wi-Fi key.

On Android 11 and later the till must declare the payment app in `android/app/src/main/AndroidManifest.xml`. Without it, the payment app looks missing even when it is installed.

```xml
<queries>
    <package android:name="com.amwalpay.pos" />
    <intent>
        <action android:name="com.amwalpay.pos.ecr.TRANSACTION" />
    </intent>
    <intent>
        <action android:name="com.amwalpay.pos.ecr.PRINT" />
    </intent>
</queries>
```

```dart
final EcrTerminal terminal = EcrTerminal.appToApp(
  serialNumber: 'P653200085189',
  config: EcrConfig(secureHashKey: wifiKey),
);
```

The answer comes back when the terminal's receipt closes: when the cashier closes it, or 15 seconds after it appears.

#### Print

App to app can also print a receipt image on the terminal's printer, after an approved sale. The image is a PNG exactly 384 pixels wide, any height, at most 15 MB. Send one print at a time.

```dart
final EcrPrintOutcome outcome = await terminal.printReceipt(
  imagePng: receiptPng,                        // 384 px wide, ≤ 15 MB
  merchantReference: approved.merchantReference,
);

switch (outcome.status) {
  case EcrPrintStatus.successful:
    showToCashier('Printed');
  case EcrPrintStatus.failed:
    showToCashier(outcome.message);            // as the payment app sent it
}
```

Wi-Fi, USB, and Web Service refuse it before anything is sent; iOS and Windows answer the same way. The width is `EcrPrintOutcome.printerWidth` and the size limit `EcrPrintOutcome.printerMaxBytes`: a wrong width or a bigger image never reaches the payment app. Build the image from the result of the operation you are printing — the example till does it in `example/lib/print/`. Do not rely on the payment app reprinting its last transaction.

`status` and `message` are separate fields. Do not merge them into one string. A print does not touch the transaction: a failed print leaves the sale exactly as it was, and you can print again.

## Operations

Amounts are `EcrAmount`, never `double`: `EcrAmount.parse('1.234')` is 1 rial and 234 baisa. `merchantReference` names this attempt. Save it before the call. Leave it blank and the SDK generates one and returns it on the result.

Every operation also has a `start…` twin — `startSale`, `startRefund`, … — that returns an `EcrOperation` with a `cancel`. **Cancelling does not undo a payment:** it ends your wait, and a cancelled sale is an unknown outcome, exactly like a timeout.

### Sale

The cardholder presents the card on the terminal.

```dart
const String reference = 'ORDER-1001-1';
save(reference);   // before the call, so a lost answer can still be looked up

final EcrResult result = await terminal.sale(
  EcrAmount.parse('1.234'),
  merchantReference: reference,
);

switch (result) {
  case EcrApproved():
    record(reference, result.amount, result.rrn, result.authCode, result.maskedPan);
    if (result.partialApproval) {
      // The bank took less than you asked: collect the rest another way.
      collectBalance(asked: result.requestedAmount, taken: result.amount);
    }
  case EcrDeclined():
    showToCashier(result.reason);   // finished: nothing was taken
  case EcrFailed() when result.settled:
    // The SDK already asked the terminal what happened, and it found the sale.
    apply(result.recoveredTransaction!);
  case EcrFailed() when result.outcomeIsUnknown:
    // The request went out and no answer settled it: the money may have moved.
    markUnresolved(reference);
  case EcrFailed():
    showToCashier(result.failure.message);   // nothing was sent, so nothing was taken
}
```

Each outcome is explained in [Read the result](#read-the-result). For an unresolved one, follow [Resolve an unknown outcome](#resolve-an-unknown-outcome).

### Void

Cancels an earlier transaction for its full amount. No card. The first argument is the receipt number (STAN). `originalTerminalId` names another terminal when the original was not taken on this one. The void has its own merchant reference.

```dart
const String voidReference = 'ORDER-1001-V1';
save(voidReference);

final EcrResult result = await terminal.voidTransaction(
  '000123',                       // the receipt number of the sale
  originalTerminalId: '',         // blank: the sale was taken on this terminal
  merchantReference: voidReference,
);

switch (result) {
  case EcrApproved():
    // The sale's full amount went back. A void has no auth code of its own.
    markVoided(order: 'ORDER-1001', rrn: result.rrn);
  case EcrDeclined():
    // For example the sale was already voided, or is no longer in the open batch.
    showToCashier(result.reason);
  case EcrFailed() when result.settled:
    apply(result.recoveredTransaction!);
  case EcrFailed() when result.outcomeIsUnknown:
    markUnresolved(voidReference);
  case EcrFailed():
    showToCashier(result.failure.message);
}
```

### Refund

Returns some or all of an earlier transaction. The cardholder presents the card. `transactionDate` is the original day, `yyyyMMdd`.

```dart
const String refundReference = 'ORDER-1001-R1';
save(refundReference);

final EcrResult result = await terminal.refund(
  EcrAmount.parse('1.000'),       // all or part of the original
  receiptNumber: '000123',        // the original's receipt number
  transactionDate: '20261019',    // the day the original was taken
  merchantReference: refundReference,
);

switch (result) {
  case EcrApproved():
    recordRefund(order: 'ORDER-1001', amount: result.amount, rrn: result.rrn);
  case EcrDeclined():
    // For example more than is left to refund, or the card does not match.
    showToCashier(result.reason);
  case EcrFailed() when result.settled:
    apply(result.recoveredTransaction!);
  case EcrFailed() when result.outcomeIsUnknown:
    markUnresolved(refundReference);
  case EcrFailed():
    showToCashier(result.failure.message);
}
```

### Inquiry by receipt number

Reads a transaction. No card, no money. Safe to repeat. The terminal answers it even while another payment is in progress.

```dart
final EcrInquiry inquiry = await terminal.inquire(
  receiptNumber: '000123',
  transactionDate: '20261019',
);

switch (inquiry) {
  case EcrInquiryFound(:final EcrTransaction transaction):
    showToCashier('${transaction.type} ${transaction.status} '
        '${transaction.amount} ${transaction.currency} · card ${transaction.maskedPan}');
    // What the terminal would accept for this transaction right now.
    voidEnabled = transaction.canVoid;
    refundEnabled = transaction.canRefund;
  case EcrInquiryNotFound(:final String reason):
    showToCashier(reason.isEmpty ? 'No transaction with that receipt number on that day' : reason);
  case EcrInquiryFailed(:final EcrFailure failure):
    showToCashier(failure.message);   // the lookup failed: ask again
}
```

### Inquiry by merchant reference

Reads the attempt you named. Use this when the sale, void, or refund never answered: you still have the reference you sent, and you do not yet have a receipt number. `transactionDate` is optional.

```dart
const String reference = 'ORDER-1001-1';   // the sale whose answer never came

switch (await terminal.inquireByReference(reference)) {
  case EcrInquiryFound(:final EcrTransaction transaction):
    switch (transaction.status.toLowerCase()) {
      case 'approved':
        apply(transaction);          // it went through: record it, do not charge again
      case 'declined':
        releaseOrder(reference);     // it did not: a new attempt needs a new reference
      default:
        markUnresolved(reference);   // voided, reversed, or anything else: leave it open
    }
  case EcrInquiryNotFound():
    // No record is not proof nothing was taken. Confirm before you charge again.
    markUnresolved(reference);
  case EcrInquiryFailed():
    retryLater(reference);           // the lookup failed: ask again
}
```

This inquiry has its own merchant reference. Leave it blank and the SDK generates one. Keep it distinct from the reference you are looking up.

### E-receipt

Wi-Fi, USB, and app to app. Returns a URL for a QR code. Safe to repeat.

```dart
final EcrReceipt receipt = await terminal.receipt(
  receiptNumber: '000123',
  transactionDate: '20261019',
);

switch (receipt) {
  case EcrReceiptReady(:final String url):
    showQr(url);                     // the customer reads the receipt on their own phone
  case EcrReceiptUnavailable(:final String reason):
    showToCashier(reason);           // no receipt to show: unknown transaction, or Web Service
  case EcrReceiptFailed(:final EcrFailure failure):
    showToCashier(failure.message);  // ask again
}
```

On Web Service the same call answers `EcrReceiptUnavailable`. `EcrTransport.supportsReceipt` says which links have it.

### Close receipt

<a id="close-receipt"></a>

Wi-Fi and USB. Asks the terminal to leave the receipt screen and return to idle. Call it from the till's Close receipt action when the cashier is finished. Sale, void, refund, and dismissing a dialog do not send it. Safe to repeat: `EcrReceiptClosedIdle` means the terminal is idle, whether a receipt was up or not. The terminal also puts its receipt away by itself 15 seconds after it appears; this clears it sooner.

```dart
// From the cashier's Close receipt button, once they are finished with the sale.
switch (await terminal.closeReceipt()) {
  case EcrReceiptClosedIdle():
    break;                                           // the terminal is on its idle screen
  case EcrReceiptClosedRefused(:final String reason):
    showToCashier(reason);                           // firmware has no CLOSE_RECEIPT; leave the receipt up
  case EcrReceiptClosedFailed(:final EcrFailure failure):
    showToCashier(failure.message);                  // nothing changed; the call can be repeated
}
```

Over app to app and Web Service the call answers `EcrReceiptClosedFailed` with `EcrUnsupported`, without sending anything: app to app has already closed the receipt by the time a till has its answer, and over Web Service the terminal's screen is not the till's to tidy (`EcrTransport.supportsCloseReceipt`).

### Settlement

<a id="settlement"></a>

Closes the terminal's current batch, the same Manual settlement as its merchant menu, and answers with the totals. Android over Wi-Fi, USB, and app to app; Windows over Wi-Fi; not iOS yet. Ask the cashier to confirm first: the terminal starts at once. Safe to repeat: a second settlement after a lost answer finds nothing to settle.

```dart
if (!await confirm('Settle the terminal now? It closes the current batch.')) return;

switch (await terminal.settlement()) {
  case final EcrSettlementSettled settled:
    showToCashier('Batch ${settled.batchId} closed: ${settled.totalTransactions} '
        'transactions, net ${settled.netAmount} ${settled.currency}');
    // Every type is present, with zeros where the batch had none.
    settled.totals.forEach((String type, EcrSettlementTotal total) =>
        showToCashier('$type × ${total.count}: ${total.amount}'));
  case EcrSettlementNothingToSettle(:final String message):
    showToCashier(message);                          // nothing was open
  case EcrSettlementNotSettled(:final String status, :final String reason,
        :final int? uploadedTransactions):
    switch (status) {
      case 'MISMATCH':
        showToCashier('Not settled: the backend counted a different number '
            '($uploadedTransactions uploaded)');
      case 'SESSION_EXPIRED':
        showToCashier('Sign the terminal in again, then settle');
      default:
        showToCashier(reason);   // FAILED, or refused before it started (96, 91, 12)
    }
  case EcrSettlementFailed(:final EcrFailure failure):
    showToCashier(failure.message);                  // safe to ask again
}
```

The terminal must be free: a transaction in progress answers `96`. It prints the settlement receipt when its profile prints, and puts the summary away 15 seconds later. Close receipt puts it away sooner.

| Result | Meaning |
|---|---|
| `EcrSettlementSettled` | The batch closed. `batchId`, `totalTransactions`, `netAmount`, and `totals` per type (`SALE`, `REFUND`, `VOID`, `PRE_AUTH`, `CAPTURE`), every type present. Amounts in major units. |
| `EcrSettlementNothingToSettle` | The batch was empty. Not a failure. |
| `EcrSettlementNotSettled` | The batch is still open. `status` is `MISMATCH` (see `uploadedTransactions`), `SESSION_EXPIRED`, `FAILED`, or empty for a refusal before it started. |
| `EcrSettlementFailed` | The exchange failed. Repeat the call. |

The terminal also settles over Web Service: the Hub relays `/Ecr/settle` to it. This package does not send that request yet, so over Web Service the call answers `EcrSettlementFailed` with `EcrUnsupported` without sending anything (`EcrTransport.supportsSettlement`).

### Sign-on

Wi-Fi and USB. Asks the terminal what it will accept before you offer operations to the cashier. Reads only. Safe to repeat.

```dart
switch (await terminal.signOn()) {
  case EcrSignOnAvailable(:final EcrTerminalCapabilities capabilities):
    // Offer only what the terminal's profile permits, within its limits.
    showOperations(capabilities.permitted.map((p) => p.type).toList());
    for (final EcrPermittedTransaction p in capabilities.permitted) {
      if (p.type == EcrTransactionType.sale) setSaleLimits(min: p.minAmount, max: p.maxAmount);
    }
  case EcrSignOnUnavailable(:final String reason):
    // The terminal is there but cannot take work now — mid-transaction, or not in ECR mode.
    showToCashier(reason);
  case EcrSignOnFailed(:final EcrFailure failure):
    showToCashier(failure.message);
}
```

Over app to app and Web Service it answers `EcrSignOnFailed` with `EcrUnsupported`, without sending anything. A request the terminal no longer permits comes back declined with its current profile attached, so a till corrects itself without signing on again.

### Reachability

Before a sale. Proves the port, cable, or payment app answers. It does not prove the terminal is idle — a terminal already taking a payment answers a handshake too.

```dart
final EcrReachability probe = await terminal.probeReachability();
if (!probe.reachable) {
  showToCashier('${probe.endpoint} is not reachable: ${probe.error}');
}
```

`isReachable()` is the same check as a `bool`. Web Service has no probe to make (`EcrTransport.hasReachabilityProbe` is false there). `probeTimeout` is 3 seconds.

## Read the result

<a id="handle-the-result"></a>

`sale`, `voidTransaction`, `refund`, and `run` return `EcrResult`.

```
EcrResult ── EcrApproved   money moved
          ├─ EcrDeclined   the terminal answered and refused
          └─ EcrFailed     no answer — see EcrFailure
```

| Result | Meaning |
|---|---|
| `EcrApproved` | Money moved. `amount` is what was taken or returned. `responseCode` is `00` on a plain approval. `maskedPan` is masked. |
| `EcrApproved` with `partialApproval` | The issuer authorised less than you asked. `requestedAmount` is what you asked. Collect the difference before you hand over the goods. |
| `EcrDeclined` | The terminal answered and refused. `reason` is the text to show. |
| `EcrFailed` and `settled` | The SDK already inquired and found it. `recoveredTransaction` is the record. |
| `EcrFailed` and `outcomeIsUnknown` | The request went out and the answer did not settle it. The payment may have completed. |
| `EcrArgumentError` | The call was rejected before anything was sent. A merchant reference longer than 32 characters, or one that contains a space, `&`, or `=`, throws here. |

| `EcrFailure` | Outcome known? | Means |
|---|---|---|
| `EcrUnreachable` | ✔ nothing happened | Nothing is listening |
| `EcrTimeout` | ✘ **unknown** | Accepted, never answered |
| `EcrMalformed` | ✘ **unknown** | Answered, illegibly |
| `EcrConnectionLost` | ✘ **unknown** | Broke part way through |
| `EcrUnauthenticated` | ✘ **unknown** | The answer could not be shown to have come from the terminal |
| `EcrCancelled` | ✘ **unknown** | You gave up waiting |
| `EcrUnsupported` | ✔ nothing happened | This platform or link cannot do it |

Response codes worth knowing (`EcrResponseCode`), all readable off `EcrDeclined`:

- `96` `isTerminalBusy` — a transaction is already running. Nothing was attempted; send again once the terminal is free. A receipt still on screen does not cause it.
- `51` with message `Card read timeout` — no card was presented within 15 seconds. Nothing was charged.
- `17` `isCancelledAtTerminal` — the operator or cardholder cancelled.
- `25` `isOriginalNotFound` — no such receipt number for that day.
- `91` — `outcomeIsUnknown` is `true`. The one decline that is not a decision.

### Inquiry

| Result | Meaning |
|---|---|
| `EcrInquiryFound` | `transaction` is the record. `status` is the outcome (`Approved`, `Declined`, `Voided`, or other text from the backend). Compare it ignoring case. |
| `EcrInquiryNotFound` | This lookup returned no record. `reason` is the backend's text when it sent any. |
| `EcrInquiryFailed` | The lookup itself failed. Repeat the inquiry. An inquiry does not move money. |

On `EcrInquiryFound`, `transaction.stan` is the receipt number. `canVoid` and `canRefund` say whether the terminal would accept that operation now.

## Important notes

### Resolve an unknown outcome

<a id="resolve-an-unknown-outcome"></a>

**A response that never arrives is not a decline.** If the socket times out or the connection breaks, the terminal may have completed the payment and been unable to say so. Treating that as a refusal and sending the request again is how a customer gets charged twice. Nothing in this package retries a money-moving request, and neither should you.

1. Save the reference before `sale`, `voidTransaction`, or `refund`.
2. Read `EcrFailed.settled` first. With `autoInquireOnFailure` left on (the default), the SDK has already inquired once; when it found the transaction, `recoveredTransaction` is the record and `outcomeIsUnknown` is false.
3. Otherwise call `inquireByReference` with the saved reference.
4. Read `transaction.status`, ignoring case.
   - `Approved` — the attempt completed. On a void or refund, the void or refund completed.
   - `Declined` — it did not. A new attempt needs a new reference.
   - Any other value, including `Voided` and `Reversed` — leave the order unresolved.
5. `EcrInquiryNotFound` after a lost answer means this lookup returned no record. Confirm on the terminal, or with Amwal, before you take payment again.
6. `EcrInquiryFailed` means the lookup failed. Inquire again.
7. On startup, inquire every attempt still marked unresolved.

`EcrUnreachable` means the connection was never made. There is no attempt to look up.

### Merchant reference

32 characters maximum, with space, `&`, and `=` excluded. Use one reference per attempt; an order number plus an attempt suffix fits. A void and a refund each get a new reference. It comes back on `EcrResult.merchantReference`, and it is the only handle you hold before the terminal answers.

### Receipt number

`EcrApproved` does not carry it. Read `transaction.stan` from an inquiry by merchant reference, or read the printed receipt. Pass that receipt's day as `yyyyMMdd` to refund, inquiry by receipt number, and e-receipt. A receipt number is unique on one terminal for one day.

### Amounts and currency

`EcrAmount.parse` from text, `EcrAmount.tryParse` for a half-typed field (null), `EcrAmount.fromMinorUnits(1234, minorUnitDigits: 3)` for minor units. The wire carries minor units — 1.234 OMR goes out as `000000001234` — converted once, using `EcrConfig.minorUnitDigits`:

| Currency | `minorUnitDigits` |
|---|---|
| OMR — 1 rial = 1000 baisa | `3` (default) |
| USD, EUR, SAR | `2` |
| JPY | `0` |

Nothing cross-checks it against `currencyCode`: getting it wrong sends every amount off by a factor of ten. Amounts come back as strings in major units (`'1.234'`), the terminal's own figure.

### Timeouts

| Transport | Wait |
|---|---|
| Wi-Fi | `connectTimeout` 10 s, then `responseTimeout` 120 s. A lost answer can add one more response wait for the automatic inquiry. |
| USB and app to app | `responseTimeout` 120 s. |
| Web Service | 130 s by default (`EcrConfig.webServiceResponseTimeout`). An explicit `responseTimeout` is kept. |

The default wait covers card present and PIN; ninety seconds is not unusual. Cancelling ends the wait in your app. A request that already reached the terminal can still complete.

### Keys

A terminal refuses what it cannot verify, so a till needs the secret Amwal issues for it. Even-length hex, at least 16 characters; a malformed one throws `EcrArgumentError` when the config is built. Wi-Fi, USB, and app to app share one key. Web Service uses its own. The app owns storage — the example keeps keys in `flutter_secure_storage` — and passes the one for the selected link on `EcrConfig.secureHashKey`. Every request is signed and every answer checked; an answer that fails the check is `EcrUnauthenticated`, an unknown outcome, never a decline. The key never belongs in source control or an app bundle, and `EcrConfig.toString` does not print it.

### Logging

A debug build logs every call and every answer. Nothing needs turning on:

```bash
adb logcat -s AmwalEcr          # Android; on iOS the Xcode console, prefixed [AmwalEcr]
```

```
AmwalEcr: -> sale op=m1k2j3-1a2b host=192.168.1.50:9100 transport=wifi
AmwalEcr: Sending SALE 4F2A9C1B7E30 to 192.168.1.50:9100
AmwalEcr: <- approved code=00
```

No `->` line: the call never left Dart. `->` but no `Sending`: refused before the socket, and the `<-` line says why. `Sending` and no `<-` for two minutes: the terminal is waiting for the cardholder. Release builds stay quiet; `adb shell setprop log.tag.AmwalEcr DEBUG` makes one talk for a session. On Windows the pure-Dart host prints comparable lines to the debug console.

## When you build the message yourself

`EcrTransactionType` is `sale`, `voidTransaction`, `refund`, `inquiry`, `receipt`, `signOn`, `closeReceipt`, `settlement`. `EcrTransactionType.menuOptions` is the operator menu: sale, void, refund, inquiry. `requiresAmount`, `requiresOriginalStan`, `requiresOriginalDate`, and `movesMoney` say which fields that operation needs. `EcrTerminal.run` accepts only the three that move money.

The wire format is in [the protocol](https://github.com/amwal-pay/ECR-simulator/blob/main/ecr-sdk/docs/protocol.md). The [integration guide](doc/integration-guide.md) has the patterns a till needs end to end, and the [release policy](RELEASING.md) covers versioning and rolling back. The example app, testing without a terminal, building, and troubleshooting are in [Development](doc/development.md).
