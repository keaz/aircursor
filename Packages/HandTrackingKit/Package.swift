// swift-tools-version: 5.10
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "HandTrackingKit",
    platforms: [.macOS(.v14)],
    products: [
        // Pure contracts + replay/record. Safe for the core packages to import.
        .library(name: "HandPoseCore", targets: ["HandPoseCore"]),
        // AVFoundation + Vision live camera source. App-target consumption only.
        .library(name: "HandTrackingKit", targets: ["HandTrackingKit"]),
    ],
    targets: [
        .target(
            name: "HandPoseCore",
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "HandTrackingKit",
            dependencies: ["HandPoseCore"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "HandTrackingKitTests",
            dependencies: ["HandTrackingKit", "HandPoseCore"],
            swiftSettings: strictConcurrency
        ),
    ]
)
