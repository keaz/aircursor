// swift-tools-version: 5.10
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "PointerControl",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PointerControl", targets: ["PointerControl"]),
    ],
    dependencies: [
        .package(path: "../GestureEngine"),
    ],
    targets: [
        .target(
            name: "PointerControl",
            dependencies: [
                .product(name: "GestureEngine", package: "GestureEngine"),
            ],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "PointerControlTests",
            dependencies: ["PointerControl"],
            swiftSettings: strictConcurrency
        ),
    ]
)
