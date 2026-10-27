# Development

The example app, testing without a terminal, building, and troubleshooting for `amwal_ecr`. Using the package is in the [README](../README.md).

## The example app

`example/` is a direct port of the Android sample till: the same two screens, the same settings, the same order of checks, the same dialogs. Where the two differ, the Android one is right and this is a bug.

- **Terminals** — register terminals by ECR mode (Wi-Fi, USB cable on Android, Web Service, app to app on Android), with separate Wi-Fi and Web Service signing keys and environment. On Windows the same UI runs over the pure-Dart host.
- **Transaction** — type, amount, receipt number, the original's date, and which terminal. It signs on before a money-moving request over Wi-Fi and USB. Close receipt is a button on the result. Manual settlement is a button under Start transaction: it asks you to confirm, then shows the batch totals. An approved app-to-app result offers Print receipt.

```bash
cd example
flutter run                 # default device
flutter run -d windows      # desktop till (Wi-Fi / Web Service)
```

Windows builds must run on a Windows host and need Visual Studio's **C++ ATL** for `flutter_secure_storage`; see [`example/README.md`](../example/README.md). An Android build that fails with `25.0.2` is Flutter using JDK 25: point it at JDK 17 with `flutter config --jdk-dir=<JDK 17>`.

### Local native SDKs (this monorepo)

The example always loads the local plugin (`amwal_ecr: path: ../`). Properties files choose how the plugin resolves the native SDKs:

| Platform | Plugin config | Example override |
|---|---|---|
| Android | `android/gradle.properties` | `example/android/gradle.properties` |
| iOS | `ios/ecr_sdk.properties` | `example/ios/ecr_sdk.properties` |

| `ecrSdkDependency` | Android | iOS |
|---|---|---|
| `project` | The sibling `ecr_sdk` Gradle module | Sibling `AmwalECR-iOS-CocoaPods` / `AmwalECR-iOS-SPM` |
| `jar` | A built JAR: `./gradlew :ecr-sdk:jar` in the SDK checkout | — |
| `maven` / `cocoapods` / `spm` | Maven Central | CocoaPods trunk or GitHub tags |

On iOS, `./tool/prepare_ios_example.sh` syncs the podspec and `Package.swift`, runs `flutter pub get` and `pod install`. Run it after changing the mode, or after adding or removing files in the CocoaPods checkout.

## Testing without a terminal

The reference repository ships a stand-in terminal:

```bash
curl -O https://raw.githubusercontent.com/amwal-pay/ECR-simulator/main/tools/fake_pos_server.py

python3 fake_pos_server.py --port 9100
python3 fake_pos_server.py --port 9100 --decline 51
python3 fake_pos_server.py --port 9100 --delay 130   # a timeout
```

Point the example at the machine running it.

## Building and testing

```bash
flutter test                    # the Dart API and the channel contract
cd example && flutter test      # the example app
./tool/run_swift_tests.sh       # the iOS bridge, no simulator needed
cd example/android && ./gradlew :amwal_ecr:testDebugUnitTest   # the Android host
```

Signing placeholders for tests come from `EcrTestConfigs`. Never commit real Amwal keys. The wire protocol is tested in the native SDKs — [AmwalECR-iOS-SPM](https://github.com/amwal-pay/AmwalECR-iOS-SPM) and `ecr-sdk` in the [reference repository](https://github.com/amwal-pay/ECR-simulator).

End to end, on a device, against a real terminal:

```bash
cd example
flutter test integration_test/app_test.dart \
  --dart-define=ECR_HOST=192.168.1.50 \
  --dart-define=ECR_SERIAL=P653200085189
```

Money-moving cases are skipped unless `--dart-define=ECR_ALLOW_FINANCIAL=true`, so a stray CI run cannot charge anybody.

### Continuous integration and distribution

[`codemagic.yaml`](../codemagic.yaml) runs the four suites on every push and pull request, builds the example APK, and builds the example for iOS with both CocoaPods and Swift Package Manager. A `vX.Y.Z` tag publishes to pub.dev after checking that the tag, `pubspec.yaml`, and `CHANGELOG.md` agree; see [the release policy](../RELEASING.md#first-time-setup).

The example reaches testers from a tag:

```bash
git tag example-ios-1     && git push origin example-ios-1      # → TestFlight, group "Testers"
git tag example-android-1 && git push origin example-android-1  # → Firebase App Distribution, group "tester"
git tag example-windows-1 && git push origin example-windows-1  # → Windows Release zip artifact
```

Firebase workflows read the Codemagic environment group `A`: `FIREBASE_SERVICE_ACCOUNT` and `FIREBASE_ANDROID_APP_ID`.

## Troubleshooting

### A sale comes back `96`

> Declined — A transaction is already in progress on this terminal

The terminal's state, not a wrapper error. Nothing was attempted, so nothing has to be reconciled. Either the terminal is already serving another ECR request, or its own transaction screen is open — a card being read, a status screen up — and the POS app refuses every money-moving request until it closes. A receipt still on screen no longer causes it: the terminal puts the receipt away after 15 seconds, and a new sale sent while it is up starts after a 3-second notice. A terminal that still answers `96` there runs an older POS app.

An **inquiry still works** while the terminal is busy: one that succeeds while a sale is refused proves the network, the plugin and the protocol are fine. To clear it, get the terminal back to its idle payment screen; if it looks idle and still refuses, restart the POS app. To avoid it, send one request at a time and keep the buttons disabled until it answers.

### Nothing answers at all

`isReachable()` returns `false`, or a sale fails with `EcrUnreachable`:

- the terminal's TMS profile must be ECR mode on the link you are using;
- the terminal must be on its idle screen;
- the till and the terminal must route to each other: no client isolation, and an Android emulator cannot reach a device on your Wi-Fi without port forwarding — use a real phone;
- on iOS, the local network permission may have been refused;
- on Windows, check the firewall, keep the project on local NTFS (plugin symlinks), and do not target USB cable.

### Windows example fails to build (`flutter_secure_storage_windows_plugin.vcxproj`)

**C++ ATL is missing** from Visual Studio (`atlstr.h` / `atls.lib`). Install **Desktop development with C++** plus **C++ ATL for latest v143 build tools**, then `flutter clean` and rebuild. Full steps: [`example/README.md`](../example/README.md#windows-visual-studio-required).

## Licence

Apache 2.0. See [LICENSE](../LICENSE).
