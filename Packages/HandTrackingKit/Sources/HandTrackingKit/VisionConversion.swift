import CoreGraphics
import HandPoseCore
import Vision

/// Converts Vision hand-pose observations into `HandPoseFrame` space.
/// Public so the offline `fixture-extract` tool shares the exact conversion
/// the live camera source uses.
public enum VisionConversion {
    /// Vision points are normalized with a bottom-left origin and unmirrored;
    /// `HandPoseFrame` space is top-left origin and mirrored horizontally so
    /// moving the hand right increases x. Both axes flip.
    public static func handSpacePoint(fromVision point: CGPoint) -> CGPoint {
        CGPoint(x: 1 - point.x, y: 1 - point.y)
    }

    public static func handJoint(for name: VNHumanHandPoseObservation.JointName) -> HandJoint? {
        switch name {
        case .wrist: return .wrist
        case .thumbCMC: return .thumbCMC
        case .thumbMP: return .thumbMP
        case .thumbIP: return .thumbIP
        case .thumbTip: return .thumbTip
        case .indexMCP: return .indexMCP
        case .indexPIP: return .indexPIP
        case .indexDIP: return .indexDIP
        case .indexTip: return .indexTip
        case .middleMCP: return .middleMCP
        case .middlePIP: return .middlePIP
        case .middleDIP: return .middleDIP
        case .middleTip: return .middleTip
        case .ringMCP: return .ringMCP
        case .ringPIP: return .ringPIP
        case .ringDIP: return .ringDIP
        case .ringTip: return .ringTip
        case .littleMCP: return .littleMCP
        case .littlePIP: return .littlePIP
        case .littleDIP: return .littleDIP
        case .littleTip: return .littleTip
        default: return nil
        }
    }

    /// Builds a frame from an observation, dropping joints below
    /// `minimumConfidence`.
    public static func frame(
        from observation: VNHumanHandPoseObservation,
        timestamp: TimeInterval,
        minimumConfidence: Float
    ) -> HandPoseFrame {
        var joints: [HandJoint: CGPoint] = [:]
        if let recognized = try? observation.recognizedPoints(.all) {
            joints.reserveCapacity(recognized.count)
            for (visionName, point) in recognized {
                guard point.confidence >= minimumConfidence,
                      let joint = handJoint(for: visionName)
                else { continue }
                joints[joint] = handSpacePoint(fromVision: point.location)
            }
        }
        return HandPoseFrame(joints: joints, timestamp: timestamp)
    }
}
