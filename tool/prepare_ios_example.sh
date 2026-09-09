#!/usr/bin/env bash
# Prepare the example iOS app against the local plugin + selected AmwalECR mode.
#
# 1) Syncs plugin Package.swift / podspec / example SPM flag from ecr_sdk.properties
# 2) flutter pub get (loads path: ../ plugin into the example)
# 3) pod install (CocoaPods face; skipped meaningful override when mode=spm)
#
# From the plugin root:
#   ./tool/prepare_ios_example.sh
#   ECR_SDK_DEPENDENCY=cocoapods ./tool/prepare_ios_example.sh
#
# Then:
#   cd example && flutter run
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
example="$root/example"
ios="$example/ios"

"$root/tool/sync_ios_ecr_sdk.sh"

cd "$example"
flutter pub get

cd "$ios"
pod install

echo
echo "iOS example ready (plugin ios/ loaded via path dependency)."
echo "  cd example && flutter run"
echo
echo "Modes: edit ios/ecr_sdk.properties or example/ios/ecr_sdk.properties"
echo "  project | cocoapods | spm   then re-run this script."
