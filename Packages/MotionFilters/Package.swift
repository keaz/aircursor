// swift-tools-version: 5.10
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "MotionFilters",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MotionFilters", targets: ["MotionFilters"]),
    ],
    targets: [
        .target(
            name: "MotionFilters",
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "MotionFiltersTests",
            dependencies: ["MotionFilters"],
            swiftSettings: strictConcurrency
        ),
    ]
)
