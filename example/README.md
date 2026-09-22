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
flutter run -d windows   # or android / ios
```

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
  --dart-define=ECR_LIVE_IP=192.168.1.50
```

## Secure hash keys

The example owns persistence via `EcrSimulatorSettings` and
`flutter_secure_storage`. Transactions use `EcrSessions.open`.

## Codemagic

Windows release builds of this nested example are the `example-windows`
workflow in the package root `codemagic.yaml` (tag `example-windows-*` or
branch `release/example`).

## Tests

```bash
flutter test
```

Signing placeholders: `test/support/ecr_test_configs.dart` (`lan` /
`lanOther` / `webService`). Never commit real Amwal keys.
