import Foundation
import HandPoseCore

/// Every gesture threshold lives here — no magic numbers inline in the engine.
///
/// Pinch metrics are tip-to-tip distances normalized by the wrist–middleMCP
/// distance, so thresholds are invariant to how far the hand is from the
/// camera.
public struct GestureConfig: Equatable, Sendable {
    /// Normalized pinch metric below which a pinch engages.
    public var pinchCloseThreshold: Double
    /// Normalized pinch metric above which a pinch releases (> close, for
    /// hysteresis).
    public var pinchOpenThreshold: Double
    /// Pinch released within this interval (and under `tapMovement`) is a tap.
    public var tapDuration: TimeInterval
    /// Maximum normalized hand travel for a pinch to still count as a tap.
    /// Exceeding it commits an index pinch to clutch-move (and a middle
    /// pinch to scrolling); staying under it past `tapDuration` arms a drag.
    public var tapMovement: Double
    /// The joint whose translation drives cursor movement. MCPs track the
    /// palm and stay stable while the fingertips articulate a pinch.
    public var movementJoint: HandJoint
    /// How long the engine coasts through missing joints (Vision dropouts)
    /// before declaring the hand lost and going idle.
    public var trackingLossGrace: TimeInterval

    public init(
        pinchCloseThreshold: Double = 0.35,
        pinchOpenThreshold: Double = 0.55,
        tapDuration: TimeInterval = 0.25,
        tapMovement: Double = 0.02,
        movementJoint: HandJoint = .indexMCP,
        trackingLossGrace: TimeInterval = 0.1
    ) {
        self.pinchCloseThreshold = pinchCloseThreshold
        self.pinchOpenThreshold = pinchOpenThreshold
        self.tapDuration = tapDuration
        self.tapMovement = tapMovement
        self.movementJoint = movementJoint
        self.trackingLossGrace = trackingLossGrace
    }
}
