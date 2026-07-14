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
        .package(
            url: "https://github.com/microsoft/onnxruntime-swift-package-manager",
            exact: "1.19.2"
        ),
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
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ],
            resources: [
                // MediaPipe-origin ONNX models (OpenCV Zoo, Apache-2.0). See
                // Resources/MODELS.md for provenance and licensing.
                .copy("Resources/palm_detection_mediapipe.onnx"),
                .copy("Resources/handpose_estimation_mediapipe.onnx"),
            ],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "HandLandmarkPipelineTests",
            dependencies: ["HandLandmarkPipeline"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "OnnxHandTrackingTests",
            dependencies: ["OnnxHandTracking"],
            swiftSettings: strictConcurrency
        ),
    ]
)
