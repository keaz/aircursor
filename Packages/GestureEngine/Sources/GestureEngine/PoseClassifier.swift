import CoreGraphics
import Foundation
import HandPoseCore
import MotionFilters

/// The v2 pose vocabulary. Poses are hand *shapes*; what they mean (button,
/// zoom arming, scroll) is the engine's business.
public enum HandPose: Equatable, Sendable {
    /// No recognized shape — relaxed hand, fist, undefined combinations.
    /// The "finger lifted off the trackpad" state.
    case neutral
    /// Index extended, middle/ring/little curled: cursor movement.
    case point
    /// Thumb–index pinch gate closed. Button or zoom depending on how the
    /// engine saw it form.
    case pinched
    /// Index+middle extended, ring+little curled: two-finger scroll.
    case scroll
    /// All four fingers extended: swipe/bloom substrate and rest pose.
    case openPalm
}

/// Which fingers the extension gates currently consider extended.
public struct FingerStates: Equatable, Sendable {
    public var index: Bool
    public var middle: Bool
    public var ring: Bool
    public var little: Bool

    public var extendedCount: Int {
        [index, middle, ring, little].lazy.filter { $0 }.count
    }

    public init(index: Bool, middle: Bool, ring: Bool, little: Bool) {
        self.index = index
        self.middle = middle
        self.ring = ring
        self.little = little
    }
}

/// One classified frame.
public struct PoseSnapshot: Equatable, Sendable {
    public var pose: HandPose
    public var fingers: FingerStates
    /// Thumb–index distance over the wrist–middleMCP span; drives pinch
    /// detection and zoom spread.
    public var indexPinchMetric: Double

    public init(pose: HandPose, fingers: FingerStates, indexPinchMetric: Double) {
        self.pose = pose
        self.fingers = fingers
        self.indexPinchMetric = indexPinchMetric
    }
}

/// Turns a landmark frame into a `PoseSnapshot`. Pure value type; all
/// temporal smoothing is hysteresis on the pinch gate and per-finger
/// extension gates (thresholds calibrated against the user's recordings:
/// extended fingers read 1.3–1.5, curled 0.4–0.8).
public struct PoseClassifier: Sendable {
    public let config: GestureConfig

    private var pinchGate: HysteresisGate
    private var indexGate: RisingHysteresisGate
    private var middleGate: RisingHysteresisGate
    private var ringGate: RisingHysteresisGate
    private var littleGate: RisingHysteresisGate

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
        self.pinchGate = HysteresisGate(
            closeThreshold: config.pinchCloseThreshold,
            openThreshold: config.pinchOpenThreshold
        )
        func makeFingerGate() -> RisingHysteresisGate {
            RisingHysteresisGate(
                engageThreshold: config.fingerExtendThreshold,
                releaseThreshold: config.fingerRetractThreshold
            )
        }
        self.indexGate = makeFingerGate()
        self.middleGate = makeFingerGate()
        self.ringGate = makeFingerGate()
        self.littleGate = makeFingerGate()
    }

    /// Classifies one frame, or returns nil when the joints required for the
    /// pinch metric (wrist, middleMCP, thumbTip, indexTip) are missing — the
    /// engine treats that as a degraded frame. A finger with missing joints
    /// keeps its previous extension state.
    public mutating func classify(_ frame: HandPoseFrame) -> PoseSnapshot? {
        guard let pinchMetric = Self.pinchMetric(in: frame) else { return nil }

        // Missing finger joints yield nil ratios; the gate keeps its state.
        if let ratio = Self.extensionRatio(tip: .indexTip, pip: .indexPIP, in: frame) {
            indexGate.update(ratio)
        }
        if let ratio = Self.extensionRatio(tip: .middleTip, pip: .middlePIP, in: frame) {
            middleGate.update(ratio)
        }
        if let ratio = Self.extensionRatio(tip: .ringTip, pip: .ringPIP, in: frame) {
            ringGate.update(ratio)
        }
        if let ratio = Self.extensionRatio(tip: .littleTip, pip: .littlePIP, in: frame) {
            littleGate.update(ratio)
        }
        pinchGate.update(pinchMetric)

        let fingers = FingerStates(
            index: indexGate.isEngaged,
            middle: middleGate.isEngaged,
            ring: ringGate.isEngaged,
            little: littleGate.isEngaged
        )

        let pose: HandPose
        if pinchGate.isEngaged {
            pose = .pinched
        } else if fingers.index && fingers.middle && !fingers.ring && !fingers.little {
            pose = .scroll
        } else if fingers.index && !fingers.middle && !fingers.ring && !fingers.little {
            pose = .point
        } else if fingers.extendedCount == 4 {
            pose = .openPalm
        } else {
            pose = .neutral
        }

        return PoseSnapshot(pose: pose, fingers: fingers, indexPinchMetric: pinchMetric)
    }

    public mutating func reset() {
        pinchGate.reset()
        indexGate.reset()
        middleGate.reset()
        ringGate.reset()
        littleGate.reset()
    }

    // MARK: - Metrics

    private static func extensionRatio(
        tip: HandJoint, pip: HandJoint, in frame: HandPoseFrame
    ) -> Double? {
        guard let wrist = frame.joints[.wrist],
              let tipPoint = frame.joints[tip],
              let pipPoint = frame.joints[pip]
        else { return nil }

        let pipDistance = distance(pipPoint, wrist)
        guard pipDistance > .ulpOfOne else { return nil }
        return distance(tipPoint, wrist) / pipDistance
    }

    /// Thumb–index distance normalized by the wrist–middleMCP span.
    static func pinchMetric(in frame: HandPoseFrame) -> Double? {
        guard let thumb = frame.joints[.thumbTip],
              let index = frame.joints[.indexTip],
              let wrist = frame.joints[.wrist],
              let middleMCP = frame.joints[.middleMCP]
        else { return nil }
        let span = hypot(wrist.x - middleMCP.x, wrist.y - middleMCP.y)
        guard span > .ulpOfOne else { return nil }
        return hypot(thumb.x - index.x, thumb.y - index.y) / span
    }
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    hypot(a.x - b.x, a.y - b.y)
}
