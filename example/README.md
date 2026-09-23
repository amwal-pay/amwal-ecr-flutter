# AmwalECR Flutter example (package nested)

Sample till app for `amwal_ecr`, nested under this package so CI and
contributors always exercise the working tree:

```yaml
amwal_ecr:
  path: ../
```

Platforms: **Android**, **iOS**, and **Windows** (LAN Wi‑Fi + Web Service; USB
cable is Android-only).

The standalone distributor repo
[`AmwalECR-flutter-example`](https://github.com/amwal-pay/AmwalECR-flutter-example)
mirrors this app with `path: ../amwal-ecr-flutter` for sibling checkouts.

## Run

```bash
cd example
flutter pub get
flutter run              # default device
flutter run -d windows   # Windows host only
flutter run -d android
flutter run -d ios
```

`flutter run -d windows` / `flutter build windows` work **only on a Windows
machine** (or Codemagic). They cannot run on macOS or Linux.

## Windows setup

### What Windows supports

| Mode | Windows |
|------|---------|
| App to app | ✘ — Android only |
| Wi‑Fi (LAN TCP, port 9100) | ✔ |
| Web Service (Hub REST) | ✔ |
| USB cable | ✘ — typed unsupported (Android only) |
| Bluetooth | ✘ |

`amwal_ecr` itself uses a pure-Dart Windows host — no extra ECR native plugin.
The example still depends on `flutter_secure_storage`, which **does** build a
native Windows plugin and needs Visual Studio ATL (below).

### Windows Visual Studio (required)

Without **C++ ATL**, MSBuild fails with a truncated error that ends in:

```text
…\flutter_secure_storage_windows_plugin.vcxproj]
No such file or directory
```

(often the real missing pieces are `atlstr.h` / `atls.lib`).

1. Open **Visual Studio Installer** → **Modify** on VS 2022
2. Workload: **Desktop development with C++**
3. Individual components: **C++ ATL for latest v143 build tools (x86 & x64)**
   (plus the Windows 10/11 SDK Flutter uses)
4. Clean and rebuild:

```bat
cd example
flutter clean
rmdir /s /q build
flutter pub get
flutter doctor -v
flutter run -d windows
```

Also keep the project on local **NTFS** (not OneDrive-only sync, a network
share, or a ReFS Dev Drive) so plugin symlinks under
`windows\flutter\ephemeral\.plugin_symlinks` can be created.

If Debug still fails after ATL is installed:

```bat
flutter run -d windows --release
```

### Firewall and network

Allow the app for outbound TCP to the terminal and HTTPS to the Hub. The PC and
POS terminal must route to each other (guest Wi‑Fi with client isolation will
not work).

## Live config (`--dart-define`)

Seeds fill **empty** secure-storage / preference slots and can register one
terminal when the list is empty — they never overwrite saved values.

| Define | Purpose |
|--------|---------|
| `ECR_ENVIRONMENT` | `SIT` / `UAT` / `PROD` |
| `ECR_WIFI_SECURE_HASH_KEY` | LAN signing secret (hex) |
| `ECR_WS_SECURE_HASH_KEY` | Web Service signing secret (hex) |
| `ECR_LIVE_MODE` | `wifi` (default) or `webService` |
| `ECR_LIVE_SERIAL` | Serial for the seeded terminal (required to seed) |
| `ECR_LIVE_TERMINAL_NAME` | Display name (default `Live terminal`) |
| `ECR_LIVE_IP` / `ECR_LIVE_PORT` | LAN address (port default `9100`) |
| `ECR_LIVE_MERCHANT_ID` / `ECR_LIVE_TERMINAL_ID` | Web Service ids |

```bash
flutter run -d windows \
  --dart-define=ECR_ENVIRONMENT=SIT \
  --dart-define=ECR_WIFI_SECURE_HASH_KEY=<hex> \
  --dart-define=ECR_LIVE_MODE=wifi \
  --dart-define=ECR_LIVE_SERIAL=SN123 \
  --dart-define=ECR_LIVE_IP=192.168.1.50 \
  --dart-define=ECR_LIVE_PORT=9100
```

## Secure hash keys

The example owns persistence via `EcrSimulatorSettings` and
`flutter_secure_storage` (Keychain / Keystore / Windows credential store).
Transactions use `EcrSessions.open`.

## Codemagic

Windows release builds of this nested example are the `example-windows`
workflow in the package root `codemagic.yaml` (tag `example-windows-*` or
branch `release/example`). Artifact: zipped `Release` runner folder.

```bash
git tag example-windows-1 && git push origin example-windows-1
```

## Tests

```bash
flutter test
```

Signing placeholders: `test/support/ecr_test_configs.dart` (`lan` /
`lanOther` / `webService`). Never commit real Amwal keys.
