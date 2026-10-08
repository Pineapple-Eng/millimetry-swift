// swift-tools-version: 6.0
// The Millimetry Swift SDK: privacy-first product analytics for Apple platforms.
// No third-party dependencies; Swift 6 language mode with strict concurrency.

import PackageDescription

let package = Package(
    name: "Millimetry",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Millimetry", targets: ["Millimetry"]),
    ],
    targets: [
        .target(
            name: "Millimetry",
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "MillimetryTests",
            dependencies: ["Millimetry"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
