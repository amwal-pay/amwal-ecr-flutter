// swift-tools-version: 5.9
import PackageDescription

// The Swift Package Manager face of the Flutter plugin, for projects built with
// `flutter config --enable-swift-package-manager`. CocoaPods remains supported
// through ../amwal_ecr.podspec, which builds the same sources and declares the
// same AmwalECR range — change one and change the other.
let package = Package(
    name: "amwal_ecr",
    platforms: [
        .iOS("12.0"),
    ],
    products: [
        .library(name: "amwal-ecr", targets: ["amwal_ecr"]),
    ],
    dependencies: [
        // The wire protocol: its own package, used unchanged by native iOS
        // apps. Ranged to the patch line for the reason given in the podspec.
        .package(
            url: "https://github.com/amwal-pay/AmwalECR-iOS-SPM.git",
            .upToNextMinor(from: "0.2.0")
        ),
    ],
    targets: [
        .target(
            name: "amwal_ecr",
            // SwiftPM identifies a package by the last component of its URL,
            // not by the `name:` in its manifest, so the package is named
            // AmwalECR-iOS-SPM here and the product AmwalECR.
            dependencies: [
                .product(name: "AmwalECR", package: "AmwalECR-iOS-SPM"),
            ]
        ),
    ]
)
