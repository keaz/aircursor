import Foundation

/// Locates the ONNX models bundled with this target (see Resources/MODELS.md).
enum BundledModels {
    static var palmDetectorURL: URL? {
        Bundle.module.url(forResource: "palm_detection_mediapipe", withExtension: "onnx")
    }

    static var handLandmarkerURL: URL? {
        Bundle.module.url(forResource: "handpose_estimation_mediapipe", withExtension: "onnx")
    }
}
