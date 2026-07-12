// swift-tools-version: 5.10
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "GestureEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GestureEngine", targets: ["GestureEngine"]),
    ],
    dependencies: [
        // Pure contracts only — never the HandTrackingKit camera product.
        .package(path: "../HandTrackingKit"),
        .package(path: "../MotionFilters"),
    ],
    targets: [
        .target(
            name: "GestureEngine",
            dependencies: [
                .product(name: "HandPoseCore", package: "HandTrackingKit"),
                .product(name: "MotionFilters", package: "MotionFilters"),
            ],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "GestureEngineTests",
            dependencies: ["GestureEngine"],
            swiftSettings: strictConcurrency
        ),
    ]
)
