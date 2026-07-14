import CoreGraphics
import Foundation
import HandPoseCore

/// Tunables for the two-stage pipeline.
public struct PipelineConfig: Equatable, Sendable {
    /// Minimum palm-detection score to start a track. This is the
    /// phantom gate Vision could not offer.
    public var palmScoreThreshold: Double
    /// Minimum landmark presence to keep a track alive; below it the track
    /// drops and the next frame re-runs the palm detector.
    public var landmarkPresenceThreshold: Double
    /// Palm box → landmark crop enlargement (MediaPipe ≈ 2.6).
    public var palmCropScale: Double
    /// Previous-landmarks bbox → next crop enlargement while following.
    public var trackCropScale: Double

    public init(
        palmScoreThreshold: Double = 0.5,
        landmarkPresenceThreshold: Double = 0.5,
        palmCropScale: Double = 2.6,
        trackCropScale: Double = 1.8
    ) {
        self.palmScoreThreshold = palmScoreThreshold
        self.landmarkPresenceThreshold = landmarkPresenceThreshold
        self.palmCropScale = palmCropScale
        self.trackCropScale = trackCropScale
    }
}

/// Drives the MediaPipe-style two-stage model: detect a palm once, then
/// follow the hand frame-to-frame by re-cropping from the previous
/// landmarks, only re-running the palm detector when the track is lost. Emits
/// a `HandPoseFrame` per frame (empty when no hand), so it slots straight
/// behind the `HandPoseSource` seam.
///
/// Pure and synchronous: the concrete source runs it on its capture queue.
/// Inference errors are treated as a detection loss so one bad frame never
/// breaks the stream; the last error is exposed for debugging.
public struct HandTrackingPipeline<Model: HandDetectionModel>: @unchecked Sendable {
    public var config: PipelineConfig
    public private(set) var isTracking = false
    public private(set) var lastError: Error?

    private let model: Model
    /// The crop to run the landmark model on next; nil means "no active
    /// track — run the palm detector".
    private var currentCrop: CGRect?

    public init(model: Model, config: PipelineConfig = PipelineConfig()) {
        self.model = model
        self.config = config
    }

    /// Processes one frame and returns the hand pose (empty joints on no
    /// hand). `image` is whatever the model consumes (a pixel buffer for the
    /// ONNX model, a stub in tests).
    public mutating func process(_ image: Model.Image, timestamp: TimeInterval) -> HandPoseFrame {
        lastError = nil

        // Stage 1 — acquire a crop if there is no active track.
        if currentCrop == nil {
            do {
                guard let palm = try model.detectPalm(in: image),
                      palm.score >= config.palmScoreThreshold
                else {
                    return lost(timestamp)
                }
                currentCrop = HandCropGeometry.squareCrop(around: palm.box, scale: config.palmCropScale)
            } catch {
                lastError = error
                return lost(timestamp)
            }
        }

        // Stage 2 — locate landmarks in the current crop and follow the hand.
        guard let crop = currentCrop else { return lost(timestamp) }
        do {
            guard let landmarks = try model.locateLandmarks(in: image, crop: crop),
                  landmarks.presence >= config.landmarkPresenceThreshold
            else {
                return lost(timestamp)
            }

            let imagePoints = HandCropGeometry.imagePoints(
                fromCropNormalized: landmarks.points, crop: crop
            )
            // Re-crop from these landmarks for the next frame — the palm
            // detector is skipped while the track holds.
            if let bbox = HandCropGeometry.boundingBox(of: imagePoints) {
                currentCrop = HandCropGeometry.squareCrop(around: bbox, scale: config.trackCropScale)
            }
            isTracking = true
            return MediaPipeLandmarks.frame(
                from: HandLandmarks(points: imagePoints, presence: landmarks.presence),
                timestamp: timestamp,
                minimumPresence: config.landmarkPresenceThreshold
            )
        } catch {
            lastError = error
            return lost(timestamp)
        }
    }

    /// Drops any active track; the next frame re-runs the palm detector.
    public mutating func reset() {
        currentCrop = nil
        isTracking = false
        lastError = nil
    }

    private mutating func lost(_ timestamp: TimeInterval) -> HandPoseFrame {
        currentCrop = nil
        isTracking = false
        return HandPoseFrame(joints: [:], timestamp: timestamp)
    }
}
