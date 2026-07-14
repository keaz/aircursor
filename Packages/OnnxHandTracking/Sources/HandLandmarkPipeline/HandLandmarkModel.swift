import CoreGraphics

/// A hand/palm region detection: a bounding box in image-normalized
/// coordinates (top-left origin) plus a **presence score** — the signal
/// Apple Vision does not provide (its confidence is pinned at 1.0). The score
/// is what lets the pipeline reject a mis-detected background "hand".
public struct PalmDetection: Equatable, Sendable {
    /// Image-normalized [0,1], top-left origin.
    public var box: CGRect
    /// Detection confidence, 0...1.
    public var score: Double
    /// In-plane rotation of the hand (radians), if the detector supplies it.
    public var rotation: Double?

    public init(box: CGRect, score: Double, rotation: Double? = nil) {
        self.box = box
        self.score = score
        self.rotation = rotation
    }
}

/// The 21 hand landmarks from the landmark model, in image-normalized
/// coordinates (top-left origin), plus the model's own presence score.
public struct HandLandmarks: Equatable, Sendable {
    /// Exactly 21 points in MediaPipe order (see `MediaPipeLandmarks`).
    public var points: [CGPoint]
    /// The landmark model's hand-presence score, 0...1.
    public var presence: Double

    public init(points: [CGPoint], presence: Double) {
        self.points = points
        self.presence = presence
    }
}

/// The two-stage MediaPipe-style model the pipeline drives. Generic over the
/// concrete image type so the pipeline is unit-testable with a fake model and
/// carries no CoreVideo/ONNX dependency.
///
/// - `detectPalm` runs on a full frame (used when there is no active track).
/// - `locateLandmarks` runs on a crop of the frame (used every frame while a
///   hand is being followed).
public protocol HandDetectionModel {
    associatedtype Image

    /// Full-frame palm search. Returns nil when no hand is found.
    func detectPalm(in image: Image) throws -> PalmDetection?

    /// Landmark localization within `crop` (image-normalized). Returns nil
    /// when the crop holds no hand.
    func locateLandmarks(in image: Image, crop: CGRect) throws -> HandLandmarks?
}
