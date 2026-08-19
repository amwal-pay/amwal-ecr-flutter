# Release policy

How the three artifacts are versioned, in what order they go out, and how to get
back if it goes wrong.

| Artifact | Registry | Repository | Tag | Versioned by |
|---|---|---|---|---|
| `com.amwal-pay:ecr-sdk` | Maven Central | [ECR-simulator](https://github.com/amwal-pay/ECR-simulator) | — | `ecr-sdk/build.gradle` |
| `AmwalECR` (SwiftPM) | SwiftPM, from the repository's tags | [AmwalECR-iOS-SPM](https://github.com/amwal-pay/AmwalECR-iOS-SPM) | **`vX.Y.Z`** | the tag itself |
| `AmwalECR` (pod) | CocoaPods trunk | [AmwalECR-iOS-CocoaPods](https://github.com/amwal-pay/AmwalECR-iOS-CocoaPods) | **`vX.Y.Z`** | `AmwalECR.podspec` |
| `amwal_ecr` | pub.dev | [amwal-ecr-flutter](https://github.com/amwal-pay/amwal-ecr-flutter) | `vX.Y.Z` | `pubspec.yaml` |

Each has its own repository and its own changelog, and they version
independently — a fix to the Swift socket is not a reason to republish the Dart
package. **The two iOS repositories hold the same sources and release under the
same version**: they are one library with two distribution faces, and a version
that exists on one and not the other is a broken release, not a partial one.

**The iOS tags have to be plain semver.** SwiftPM reads `vX.Y.Z` or `X.Y.Z` and
nothing else. Tagging an iOS release `ios-v0.2.0` publishes a version no SwiftPM
consumer can resolve.

---

## Versioning

Semantic versioning, with one addition: **any change to the platform-channel
contract is breaking**, whatever it looks like from Dart.

A method name, an argument key, a result key, an outcome value or a failure kind
is a contract between a Dart package and a native host that ship in the same
binary but are built at different times. Renaming one is not a refactor — it is
a call that stops being answered at a till.

| Change | Version |
|---|---|
| A new optional argument, defaulted on both hosts | minor |
| A new failure kind, outcome, or result field | minor — older Dart reads an unknown kind as `EcrMalformed`, which is the safe reading |
| Renaming **anything** in the channel contract | **major** |
| Removing a field the Dart side reads | **major** |
| Raising the pinned `ecr-sdk` version, or the `AmwalECR` range | minor, and named in the changelog |
| Raising the Dart, Flutter, Android or iOS floor | **major** |
| Changing what an outcome *means* — a decline becoming a failure, `outcomeIsUnknown` changing for a case | **major**, however small the diff |

That last row is the one that matters. `outcomeIsUnknown` decides whether a till
retries. A change to it is a change to whether customers get charged twice, and
it gets a major version and a paragraph in the changelog even if it is one line
of code.

### The protocol version is separate

The `version` field in every request is the *wire* protocol's, currently `1`. It
is bumped only when the message format changes in a way older terminals cannot
read, and that is a change to the terminal, the Kotlin SDK and this package
together.

---

## Who publishes what

Each repository publishes its own artifact, by a script that also runs on a
workstation:

| Repository | Artifact | Starts on | Script |
|---|---|---|---|
| ECR-simulator | `com.amwal-pay:ecr-sdk` | by hand | `publish.sh` |
| AmwalECR-iOS-SPM | the SwiftPM package | tag `vX.Y.Z` | — the tag *is* the release |
| AmwalECR-iOS-CocoaPods | the `AmwalECR` pod | tag `vX.Y.Z` | `pod trunk push AmwalECR.podspec` |
| amwal-ecr-flutter | `amwal_ecr` | tag `vX.Y.Z` | `dart pub publish` |

Whatever drives them, publishes must be **idempotent**: a version already on the
registry is reported and skipped, not re-pushed, so a re-run of a build is never
destructive. And each one ends by reading the artifact back from the registry,
because a registry accepting a push and an integrator being able to resolve it
are two different things.

To rehearse this package's release without publishing anything:

```bash
dart pub publish --dry-run
```

---

## First-time setup

Done once, per registry, by somebody with the credentials. Until each is done,
the corresponding release step below cannot run at all.

### CocoaPods trunk

```bash
pod trunk register support@amwal-pay.com 'Amwal Pay' --description='release machine'
```

Confirm the emailed link, then copy the token out of `~/.netrc` into a
**Codemagic environment group** called `cocoapods_credentials`, as a secure
variable named `COCOAPODS_TRUNK_TOKEN`.

The **first** `pod trunk push` claims the name `AmwalECR` for whoever runs it;
everybody who releases afterwards has to be added:

```bash
pod trunk add-owner AmwalECR someone@amwal-pay.com
```

A pod name cannot be transferred or reclaimed once taken, so register it to an
address the team keeps, not to one person's inbox.

### Swift Package Manager

Nothing to register. SwiftPM resolves from [AmwalECR-iOS-SPM](https://github.com/amwal-pay/AmwalECR-iOS-SPM)'s tags, so
the package exists as soon as a `vX.Y.Z` tag is pushed — which also means a tag
pushed by mistake is a published version, to be superseded rather than deleted.

### pub.dev

On a workstation, with the Google account that owns (or will claim) the
`amwal_ecr` name:

```bash
flutter pub login
cat "$HOME/Library/Application Support/dart/pub-credentials.json"
```

Put those contents in a Codemagic environment group called `pub_credentials`, as
a secure variable named `PUB_CREDENTIALS`. Base64 of the same JSON is accepted,
which travels through variable editors more reliably than multi-line text.

**That file is a publishing credential, not a config file.** Anyone who can read
it can publish as its owner, so it does not go in the repository — not in this
one, and not in any other. A CI publish writes it at build time and it lives only
in the build machine's home directory.

---

## Release order

The wrapper depends on the providers. Publish upwards, never downwards.

```
1. ecr-sdk (Maven Central)     the Android provider
2. AmwalECR (SPM, then trunk)  the iOS provider, both faces, one version
3. amwal_ecr (pub.dev)         the Flutter bridge over both
4. the example app             smoke-tested against the published artifacts
```

Concretely, for a release that includes a native change:

1. **Publish `ecr-sdk`.** `./publish.sh` in the ECR-simulator checkout. Wait for
   it to appear on Maven Central — a version that is not yet resolvable will
   fail every integrator's first build, and "it works locally" is `mavenLocal()`
   lying.
2. **Publish `AmwalECR`, both faces.** Copy the changed sources into both iOS
   repositories, then:

   ```bash
   # AmwalECR-iOS-SPM: swift test, then the tag — the tag is the release
   swift test && git tag v0.2.0 && git push origin v0.2.0

   # AmwalECR-iOS-CocoaPods: same sources, same version
   pod lib lint AmwalECR.podspec --allow-warnings
   git tag v0.2.0 && git push origin v0.2.0
   pod trunk push AmwalECR.podspec --allow-warnings
   ```

   The SwiftPM tag is what those consumers resolve, so it goes out **before** the
   trunk push, and neither tag is ever moved afterwards: a moved tag is a
   different library under a version somebody has already locked.
3. **Pin the new versions** in `android/build.gradle`, `ios/amwal_ecr.podspec`
   and `ios/amwal_ecr/Package.swift` — the last two must name the same range —
   and update the compatibility matrix in the same commit.
4. **Run everything.** All five suites, and the integration test on a device
   from the matrix.
5. **Publish `amwal_ecr`.** `dart pub publish`, then tag `vX.Y.Z`. Do not
   publish if the `AmwalECR` version the bridge asks for is not on trunk yet.
6. **Smoke-test the published artifacts**, below.

Never publish `amwal_ecr` against a provider version that is not live —
including an `AmwalECR` that is tagged in the SwiftPM repository but not yet on
trunk, which resolves for SwiftPM users and fails for everyone on CocoaPods.

---

## Before publishing

Everything below has to pass before a release:

```bash
flutter analyze                                   # must be clean
flutter test                                      # the Dart API and the contract
(cd example && flutter test)                      # the example app
./tool/run_swift_tests.sh                         # the iOS bridge
(cd example/android && ./gradlew :amwal_ecr:testDebugUnitTest)

dart pub publish --dry-run                        # package metadata
```

And in the iOS SDK repositories, on the same sources:

```bash
swift test                                        # AmwalECR-iOS-SPM
pod lib lint AmwalECR.podspec --allow-warnings    # AmwalECR-iOS-CocoaPods
```

On a device from the matrix, against a real listener:

```bash
cd example
flutter test integration_test/app_test.dart \
  --dart-define=ECR_HOST=… --dart-define=ECR_SERIAL=…
```

Money-moving cases need `--dart-define=ECR_ALLOW_FINANCIAL=true` as well, and a
**non-production** terminal. There is no such thing as a test sale on a live
one.

---

## Smoke-testing the published artifact

A package that passes its own tests and still does not work when installed is a
recognised failure mode: a file missing from the pub archive, a podspec that
only resolved because of a local path, a Gradle dependency that only existed in
`mavenLocal()`. So the check is done against the published version, not the
working tree:

```bash
flutter create --platforms=android,ios /tmp/ecr_smoke
cd /tmp/ecr_smoke
flutter pub add amwal_ecr          # the published version, no path override
```

Then, in `lib/main.dart`, the smallest thing that exercises the whole path:

```dart
final EcrResult result = await EcrTerminal(
  host: '127.0.0.1',
  config: EcrConfig(port: 1, connectTimeout: const Duration(seconds: 2)),
).sale(EcrAmount.parse('0.001'));

// EcrUnreachable means the plugin is registered and the socket was really
// attempted. EcrUnsupported means it is not registered — the package did not
// install correctly.
print(result);
```

```bash
flutter build apk --debug
flutter build ios --no-codesign
flutter run          # on one Android and one iOS device
```

Both builds passing and the call answering `EcrUnreachable` is the bar. Do it in
a fresh project rather than in `example/`: the example's Podfile can be pointed
at a local SDK checkout, and would not catch a pod that never landed.

### And the iOS SDK on its own

A native integrator installs neither Flutter nor this package, so that path is
smoke-tested separately:

```bash
# CocoaPods
mkdir /tmp/ecr_pod_smoke && cd /tmp/ecr_pod_smoke
pod spec cat AmwalECR                       # it is on trunk and the JSON is sane

# Swift Package Manager
mkdir /tmp/ecr_spm_smoke && cd /tmp/ecr_spm_smoke && swift package init
# add the package dependency, then:
swift build
```

```swift
import AmwalECR

let terminal = EcrTerminal(host: "127.0.0.1", config: EcrConfig(port: 1, connectTimeout: 2))
print(terminal.isReachable())   // false, quickly — the module is public and linked
```

The point of the snippet is not the answer but the compile: every type a till
touches has to be `public`, and a type left `internal` is invisible to
integrators while remaining perfectly visible to the SDK's own tests.

---

## Rolling back

### What to roll back to

| Release | `amwal_ecr` | `ecr-sdk` | `AmwalECR` | Notes |
|---|---|---|---|---|
| 0.1.0 | 0.1.0 | 1.0.3 | 0.1.0 | first release |

Keep this table current. It is the only place that records which pair was ever
shipped together, and at three in the morning it is the only thing anyone wants.

### Rolling back the Flutter package

Published pub.dev versions cannot be deleted, only **retracted**:

```bash
dart pub retract amwal_ecr 0.1.1
```

Retracting stops new resolutions picking it up; it does not touch apps already
built against it. So retract **and** publish a fixed version — a retraction on
its own leaves integrators on the broken build with nowhere to go.

Integrators pin back in the meantime:

```yaml
dependencies:
  amwal_ecr: 0.1.0   # exact, not ^
```

### Rolling back the iOS provider

CocoaPods trunk releases cannot be deleted either, and a Git tag that anyone may
have resolved must not be moved or deleted. Roll back the same way: publish
`AmwalECR` `0.1.1` with the fix, tag it, push it to trunk, then bump
`amwal_ecr`'s range if the bad version is inside it.

`pod trunk deprecate AmwalECR` exists but retires the whole pod, not one
version. It is not a rollback tool.

### Rolling back the Android provider

Maven Central releases are immutable and cannot be retracted. Rolling back means
publishing a new `amwal_ecr` that pins the older `ecr-sdk`:

1. set the previous version in `android/build.gradle`;
2. bump `amwal_ecr`'s patch version;
3. run everything above;
4. publish;
5. retract the bad `amwal_ecr` version.

### If the bad release charged somebody twice

Stop shipping and reconcile first. Every till affected has the receipt numbers
it sent — that is why the guide asks tills to record them before sending — and
an inquiry against each one says what actually happened. The rollback can wait
half an hour; a duplicate charge that nobody has reconciled cannot.

---

## Deprecations

A public API that is going away is marked `@Deprecated` with the version it will
be removed in, and it keeps working for at least one minor release:

```dart
@Deprecated('Use startSale(…).result instead. Removed in 2.0.0.')
Future<EcrResult> beginSale(EcrAmount amount) => startSale(amount).result;
```

Channel contract entries are the exception: they cannot be deprecated, because
there is no way for an old host to know a new name. They are renamed in a major
version, in all three contract files and all three contract tests, in one
commit.
