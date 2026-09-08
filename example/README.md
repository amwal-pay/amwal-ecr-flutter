# amwal_ecr example

Sample till for the local `amwal_ecr` plugin — same flows as the Android ECR
simulator app.

## Secure hash keys

App-owned: secrets in **`flutter_secure_storage`**, environment in
SharedPreferences. `EcrSimulatorSettings.secureHashKeyFor` picks the LAN or
Web Service secret for `EcrConfig.secureHashKey`. The plugin never stores keys.

Use **`EcrSessions.open`** (or construct `EcrTerminal`) once per transaction
path so sale / inquiry / receipt stay on the same transport.

## Local iOS SDK

`example/ios/ecr_sdk.properties` + `../ios/ecr_sdk.properties` select
`project` | `cocoapods` | `spm`. Apply with:

```bash
./tool/prepare_ios_example.sh
```
