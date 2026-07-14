import CoreGraphics
import CoreVideo
import Foundation
import HandLandmarkPipeline

/// The concrete two-stage hand model that `HandTrackingPipeline` drives, backed
/// by ONNX Runtime and the OpenCV-Zoo MediaPipe models (see Resources/MODELS.md).
/// Its image type is `CVPixelBuffer` (camera frames).
///
/// - `detectPalm`: letterbox the whole frame to the palm detector's 192², run
///   BlazePalm, decode SSD anchors + NMS to the best `PalmDetection` (box +
///   score), and map the box from letterbox-square space back to the image.
/// - `locateLandmarks`: crop `crop` from the frame, resize to the landmark
///   model's 224², run it, and read the 21 screen landmarks + presence as
///   crop-normalized `HandLandmarks`.
///
/// Axis-aligned variant: crops are unrotated (the palm rotation is not yet
/// applied). Model-output tensor names/shapes were verified against the real
/// files: palm emits `Identity`(2016×18 regression) + `Identity_1`(2016 scores);
/// hand emits `Identity`(63 screen landmarks) + `Identity_1`(presence) [+
/// handedness + world landmarks, unused]. Outputs are resolved by element count
/// and graph order so a re-export that renames tensors still works.
public struct OnnxHandLandmarkModel: HandDetectionModel {
    public typealias Image = CVPixelBuffer

    public enum ModelError: Error, Equatable {
        case modelsMissing
        case inferenceFailed(String)
    }

    static let palmInput = 192
    static let handInput = 224
    static let palmScoreThreshold = 0.5
    static let palmIoUThreshold = 0.3

    private let palm: OrtModel
    private let hand: OrtModel
    private let preprocessor = PixelPreprocessor()

    public init() throws {
        guard let palmURL = BundledModels.palmDetectorURL,
              let handURL = BundledModels.handLandmarkerURL else {
            throw ModelError.modelsMissing
        }
        palm = try OrtModel(modelPath: palmURL.path)
        hand = try OrtModel(modelPath: handURL.path)
    }

    public func detectPalm(in image: CVPixelBuffer) throws -> PalmDetection? {
        let size = Self.palmInput
        guard let tensor = preprocessor.letterboxTensor(from: image, size: size) else {
            throw ModelError.inferenceFailed("palm preprocess")
        }
        let outputs = try palm.run(input: tensor, shape: [1, size, size, 3])
        // 2016×18 regression vs 2016 scores — unambiguous by count.
        guard let regression = outputs.values.first(where: { $0.count == 2016 * 18 }),
              let scores = outputs.values.first(where: { $0.count == 2016 }) else {
            throw ModelError.inferenceFailed("palm outputs")
        }
        guard let candidate = PalmDecode.best(
            scores: scores, regression: regression,
            modelInput: Double(size),
            scoreThreshold: Self.palmScoreThreshold,
            iouThreshold: Self.palmIoUThreshold
        ) else { return nil }

        // Map the box from letterbox-square-normalized to image-normalized.
        let w = Double(CVPixelBufferGetWidth(image)), h = Double(CVPixelBufferGetHeight(image))
        let lb = Letterbox(imageWidth: w, imageHeight: h, modelSize: Double(size))
        return PalmDetection(box: lb.imageNormalized(candidate.box), score: candidate.score, rotation: nil)
    }

    public func locateLandmarks(in image: CVPixelBuffer, crop: CGRect) throws -> HandLandmarks? {
        let size = Self.handInput
        guard let tensor = preprocessor.cropTensor(from: image, crop: crop, size: size) else {
            throw ModelError.inferenceFailed("landmark preprocess")
        }
        let outputs = try hand.run(input: tensor, shape: [1, size, size, 3])
        // Screen landmarks = first 63-count output (graph order: `Identity`);
        // presence = first 1-count output (`Identity_1`), before handedness.
        guard let landmarks = firstOutput(outputs, names: hand.outputNames, count: 63),
              let presence = firstOutput(outputs, names: hand.outputNames, count: 1)?.first else {
            throw ModelError.inferenceFailed("landmark outputs")
        }
        return HandLandmarkDecode.result(landmarks: landmarks, presence: presence, modelInput: Double(size))
    }

    /// The first output (in graph declaration order) whose flat length matches.
    private func firstOutput(_ outputs: [String: [Float]], names: [String], count: Int) -> [Float]? {
        for name in names {
            if let v = outputs[name], v.count == count { return v }
        }
        return nil
    }
}
