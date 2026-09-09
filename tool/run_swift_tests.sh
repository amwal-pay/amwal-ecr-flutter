#!/usr/bin/env bash
# Runs the Flutter plugin's Swift bridge tests.
#
# Everything in ios/amwal_ecr/Sources/amwal_ecr except AmwalEcrPlugin.swift is
# free of Flutter — the handler, the mapping, the contract, the port. That is on
# purpose: it means the logic that decides what a till is told can be tested
# with plain `swift test`, on any Mac, in seconds, with no simulator, no Xcode
# project and no Runner app.
#
# The wire protocol itself is not here. It lives in the AmwalECR SDK, which is
# its own repository and has its own suite.
#
# SwiftPM will not read sources from outside its own directory, so the bridge is
# assembled in a temporary directory from a copy of the real sources, with the
# SDK as a dependency. The copy is the point: if a file grows an
# `import Flutter`, the build fails here rather than the test quietly stopping
# being run.
#
#   ./tool/run_swift_tests.sh
#
# Honours ios/ecr_sdk.properties (and example overrides) when mode=project:
# uses the sibling AmwalECR-iOS-SPM checkout. Override explicitly with:
#
#   AMWAL_ECR_SDK_PATH=../AmwalECR-iOS-SPM ./tool/run_swift_tests.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/Sources/AmwalEcrBridge" "$work/Tests/AmwalEcrBridgeTests"

# Every bridge source except the one that talks to Flutter.
find "$root/ios/amwal_ecr/Sources/amwal_ecr" -name '*.swift' ! -name 'AmwalEcrPlugin.swift' \
  -exec cp {} "$work/Sources/AmwalEcrBridge/" \;
cp "$root"/ios/Tests/*.swift "$work/Tests/AmwalEcrBridgeTests/"

load_prop() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    local k="${line%%=*}"
    local v="${line#*=}"
    k="$(echo "$k" | xargs)"
    v="$(echo "$v" | xargs)"
    if [[ "$k" == "$key" ]]; then
      echo "$v"
      return 0
    fi
  done < "$file"
}

mode="$(load_prop "$root/example/ios/ecr_sdk.properties" ecrSdkDependency)"
mode="${mode:-$(load_prop "$root/ios/ecr_sdk.properties" ecrSdkDependency)}"
mode="${mode:-cocoapods}"
version="$(load_prop "$root/example/ios/ecr_sdk.properties" ecrSdkVersion)"
version="${version:-$(load_prop "$root/ios/ecr_sdk.properties" ecrSdkVersion)}"
version="${version:-0.2.1}"
spm_rel="$(load_prop "$root/example/ios/ecr_sdk.properties" ecrSdkSpmRoot)"
spm_base="$root/example/ios"
if [[ -z "$spm_rel" ]]; then
  spm_rel="$(load_prop "$root/ios/ecr_sdk.properties" ecrSdkSpmRoot)"
  spm_base="$root/ios"
fi
spm_rel="${spm_rel:-../../AmwalECR-iOS-SPM}"

# The version range here is the one ios/amwal_ecr/Package.swift and
# ios/amwal_ecr.podspec declare. Keep the three in step.
# SwiftPM identifies a package by the last component of its location, not by the
# `name:` in its manifest, so the package name below is the directory or the
# repository — never the product, which is AmwalECR either way.
if [[ -n "${AMWAL_ECR_SDK_PATH:-}" ]]; then
  sdk_path="$(cd "$AMWAL_ECR_SDK_PATH" && pwd)"
  echo "Testing against the SDK checkout at $sdk_path"
  dependency=".package(path: \"$sdk_path\"),"
  package_id="$(basename "$sdk_path")"
elif [[ "$mode" == "project" ]]; then
  sdk_path="$(cd "$spm_base/$spm_rel" && pwd)"
  echo "Testing against local AmwalECR (ecrSdkDependency=project) at $sdk_path"
  dependency=".package(path: \"$sdk_path\"),"
  package_id="$(basename "$sdk_path")"
else
  echo "Testing against the published AmwalECR SDK ($mode, $version)"
  dependency=".package(url: \"https://github.com/amwal-pay/AmwalECR-iOS-SPM.git\", .upToNextMinor(from: \"$version\")),"
  package_id="AmwalECR-iOS-SPM"
fi

cat > "$work/Package.swift" <<PACKAGE
// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "AmwalEcrBridge",
    platforms: [.macOS(.v12)],
    dependencies: [
        $dependency
    ],
    targets: [
        .target(
            name: "AmwalEcrBridge",
            dependencies: [.product(name: "AmwalECR", package: "$package_id")]
        ),
        .testTarget(name: "AmwalEcrBridgeTests", dependencies: ["AmwalEcrBridge"]),
    ]
)
PACKAGE

# The bridge's own types are `internal` to its module; the tests reach them with
# @testable, which needs the module built for testing. The SDK's types are
# public and imported normally.
echo "Running the Swift bridge tests in $work"
cd "$work"
swift test "$@"
