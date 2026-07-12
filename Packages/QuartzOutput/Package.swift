// swift-tools-version: 5.10
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "QuartzOutput",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuartzOutput", targets: ["QuartzOutput"]),
    ],
    dependencies: [
        .package(path: "../PointerControl"),
    ],
    targets: [
        .target(
            name: "QuartzOutput",
            dependencies: [
                .product(name: "PointerControl", package: "PointerControl"),
            ],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "QuartzOutputTests",
            dependencies: ["QuartzOutput"],
            swiftSettings: strictConcurrency
        ),
    ]
)
