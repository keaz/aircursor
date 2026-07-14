// swift-tools-version: 5.10
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "OnnxHandTracking",
    platforms: [.macOS(.v14)],
    products: [
        // Pure, model-independent pipeline — no ONNX dependency, unit-tested.
        .library(name: "HandLandmarkPipeline", targets: ["HandLandmarkPipeline"]),
        // The ONNX-backed HandPoseSource. Adds the ONNX Runtime dependency
        // once model files are wired (milestone O2).
        .library(name: "OnnxHandTracking", targets: ["OnnxHandTracking"]),
    ],
    dependencies: [
        // Shares the HandPoseFrame / HandPoseSource contracts.
        .package(path: "../HandTrackingKit"),
        // ONNX Runtime is added in O2 (needs the model files first):
        // .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.19.0"),
    ],
    targets: [
        .target(
            name: "HandLandmarkPipeline",
            dependencies: [
                .product(name: "HandPoseCore", package: "HandTrackingKit"),
            ],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "OnnxHandTracking",
            dependencies: [
                "HandLandmarkPipeline",
                .product(name: "HandPoseCore", package: "HandTrackingKit"),
                // .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "HandLandmarkPipelineTests",
            dependencies: ["HandLandmarkPipeline"],
            swiftSettings: strictConcurrency
        ),
    ]
)
