# Contributing to amwal_ecr

For people working on this package. Integrators need only the [README](README.md)
and [doc/](doc/).

---

## Building the example against local checkouts

**Android.** The plugin reads `ecrSdkDependency` from `android/gradle.properties`:

| `ecrSdkDependency` | Use when |
|---|---|
| `jar` (default in this repo) | Sibling `ecr_sdk` checkout — build once: `cd ../../ecr_sdk && ./gradlew :ecr-sdk:jar` |
| `project` | Live Gradle module — also set `ecrSdkDependency=project` in `example/android/gradle.properties` |
| `maven` | Published `com.amwal-pay:ecr-sdk` from Maven Central |

Paths assume `amwal-ecr-flutter` and `ecr_sdk` sit under the same parent directory.

If the Android build fails with JDK 25, uncomment `org.gradle.java.home` in
`example/android/gradle.properties` and point it at a JDK 17 install.

---

## Testing

```bash
flutter test                    # the Dart API and the channel contract
cd example && flutter test      # the example app
./tool/run_swift_tests.sh       # the iOS bridge, no simulator needed
cd example/android && ./gradlew :amwal_ecr:testDebugUnitTest   # the Android host
```

Unit tests share signing placeholders via `EcrTestConfigs` (aligned with
`ecr_sdk`): `SECURE_HASH_KEY_ECR_WIFI`, `SECURE_HASH_KEY_ECR_WIFI_OTHER`, and
`SECURE_HASH_KEY_WEBSERVICE`, exposed as `lan` / `lanOther` / `webService`
configs. Never commit real Amwal keys.

The wire protocol is not tested here: it lives in the native SDKs, each with its
own suite — [AmwalECR-iOS-SPM](https://github.com/amwal-pay/AmwalECR-iOS-SPM) on iOS, `ecr-sdk` in the
[reference repository](https://github.com/amwal-pay/ECR-simulator) on Android.

Working on the iOS SDK and this bridge together, point the bridge tests at a
checkout instead of at the published version:

```bash
AMWAL_ECR_SDK_PATH=../AmwalECR-iOS-SPM ./tool/run_swift_tests.sh
```

For the example app, uncomment the local `pod` line in `example/ios/Podfile`.
**A file added to or removed from that checkout's `Sources/AmwalECR` then needs
`pod install` in `example/ios`** before the app will build: until then Xcode
reports the new type as missing while `swift build` is clean, because the pod's
file list is a snapshot taken at install time, not a live glob.

```bash
(cd example/ios && pod install)
```

End to end, on a device, against a real listener:

```bash
cd example
flutter test integration_test/app_test.dart \
  --dart-define=ECR_HOST=192.168.1.50 \
  --dart-define=ECR_SERIAL=P653200085189
```

Money-moving cases are skipped unless `--dart-define=ECR_ALLOW_FINANCIAL=true`,
so a stray CI run cannot charge anybody.

### Continuous integration

[`codemagic.yaml`](codemagic.yaml) runs on Codemagic. Every push and pull
request runs the four suites above, builds the example APK, and builds the
example for iOS twice — once with CocoaPods, once with Flutter's Swift Package
Manager integration — so both faces of the plugin resolve `AmwalECR` from its
registry the way an integrator's build will. A `vX.Y.Z` tag publishes to
pub.dev, after checking that the tag, `pubspec.yaml` and `CHANGELOG.md` agree
and that the `AmwalECR` range the iOS host asks for is live on trunk; a version
already on pub.dev is skipped, not re-pushed. Credentials come from a Codemagic
environment group, never from the repository — see
[the release policy](RELEASING.md#first-time-setup).


---

## Releasing

See [RELEASING.md](RELEASING.md): versioning rules, release order across the
four artifacts, first-time registry setup, and how to roll back.
