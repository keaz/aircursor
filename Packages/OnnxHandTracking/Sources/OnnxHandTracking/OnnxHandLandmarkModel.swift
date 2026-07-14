import CoreGraphics
import CoreVideo
import Foundation
import HandLandmarkPipeline

/// The concrete two-stage model that `HandTrackingPipeline` drives, backed by
/// ONNX Runtime. Its image type is `CVPixelBuffer` (camera frames).
///
/// **Milestone O2 — not yet implemented.** Wiring this needs the actual model
/// files so the tensor I/O can be written against their real specs (input
/// shapes, output tensor names, and the palm detector's SSD-anchor decode),
/// rather than guessed. Until then it reports `modelNotConfigured` so the
/// package builds and the pipeline can be exercised end to end with a stub.
///
/// Steps to complete (see docs/superpowers/specs/2026-07-14-onnx-hand-tracking-design.md):
///  1. Add the `onnxruntime-swift-package-manager` SPM dependency (macOS 14).
///  2. Place Apache-2.0 palm-detection + 21-landmark `.onnx` models under
///     `Resources/` (verify licenses; avoid the GPL-3.0 GoldYOLO variant).
///  3. `detectPalm`: letterbox the full frame to the palm model's input
///     (≈192²), run it, decode SSD anchors → the top `PalmDetection`
///     (box + score), keeping the score as the presence gate.
///  4. `locateLandmarks`: crop `crop` from the buffer, resize to the landmark
///     model's input (≈224²), run it, read the 21 (x,y) + presence outputs
///     as `HandLandmarks` in crop-normalized space.
public struct OnnxHandLandmarkModel: HandDetectionModel {
    public typealias Image = CVPixelBuffer

    public enum ModelError: Error, Equatable {
        /// The ONNX model files have not been wired yet (milestone O2).
        case modelNotConfigured
        case inferenceFailed(String)
    }

    public init() {}

    public func detectPalm(in image: CVPixelBuffer) throws -> PalmDetection? {
        throw ModelError.modelNotConfigured
    }

    public func locateLandmarks(in image: CVPixelBuffer, crop: CGRect) throws -> HandLandmarks? {
        throw ModelError.modelNotConfigured
    }
}
