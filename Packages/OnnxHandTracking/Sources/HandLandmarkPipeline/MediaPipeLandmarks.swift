import CoreGraphics
import Foundation
import HandPoseCore

/// Maps the MediaPipe hand-landmark model's fixed 21-point output onto the
/// app's `HandJoint` contract and into `HandPoseFrame` coordinate space.
public enum MediaPipeLandmarks {
    /// The 21 landmarks in MediaPipe's canonical order (index 0…20). This
    /// ordering is a stable part of the model contract.
    public static let jointOrder: [HandJoint] = [
        .wrist,                                   // 0
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip, // 1–4
        .indexMCP, .indexPIP, .indexDIP, .indexTip, // 5–8
        .middleMCP, .middlePIP, .middleDIP, .middleTip, // 9–12
        .ringMCP, .ringPIP, .ringDIP, .ringTip,   // 13–16
        .littleMCP, .littlePIP, .littleDIP, .littleTip, // 17–20 (pinky)
    ]

    /// Converts an image-normalized point (top-left origin, as the model and
    /// the raw camera frame use) into `HandPoseFrame` space (top-left origin,
    /// mirrored horizontally so moving the hand right increases x — the
    /// camera preview is mirrored to match). Only x flips; y already agrees.
    ///
    /// (The Vision path flips **both** axes because Vision is bottom-left; the
    /// MediaPipe model is top-left, so y is untouched here.)
    public static func handSpacePoint(fromImageNormalized point: CGPoint) -> CGPoint {
        CGPoint(x: 1 - point.x, y: point.y)
    }

    /// Builds a `HandPoseFrame` from 21 image-normalized landmarks. Points
    /// below `minimumPresence` yield an empty frame (treated as no hand),
    /// mirroring how the Vision source reports a loss.
    ///
    /// - Precondition: `landmarks.points.count == 21`.
    public static func frame(
        from landmarks: HandLandmarks,
        timestamp: TimeInterval,
        minimumPresence: Double
    ) -> HandPoseFrame {
        guard landmarks.presence >= minimumPresence,
              landmarks.points.count == jointOrder.count
        else {
            return HandPoseFrame(joints: [:], timestamp: timestamp)
        }
        var joints: [HandJoint: CGPoint] = [:]
        joints.reserveCapacity(jointOrder.count)
        for (joint, point) in zip(jointOrder, landmarks.points) {
            joints[joint] = handSpacePoint(fromImageNormalized: point)
        }
        return HandPoseFrame(joints: joints, timestamp: timestamp)
    }
}
