import Foundation

/// Every gesture threshold lives here — no magic numbers inline in the engine.
///
/// Pinch metrics are tip-to-tip distances normalized by the wrist–middleMCP
/// distance, so thresholds are invariant to how far the hand is from the
/// camera.
public struct GestureConfig: Equatable, Sendable {
    /// Normalized pinch metric below which the thumb–index clutch engages.
    public var pinchCloseThreshold: Double
    /// Normalized pinch metric above which the clutch releases (> close, for
    /// hysteresis).
    public var pinchOpenThreshold: Double
    /// Pinch released within this interval (and under `tapMovement`) is a tap.
    public var tapDuration: TimeInterval
    /// Maximum normalized hand travel for a pinch to still count as a tap.
    public var tapMovement: Double

    public init(
        pinchCloseThreshold: Double = 0.35,
        pinchOpenThreshold: Double = 0.55,
        tapDuration: TimeInterval = 0.25,
        tapMovement: Double = 0.02
    ) {
        self.pinchCloseThreshold = pinchCloseThreshold
        self.pinchOpenThreshold = pinchOpenThreshold
        self.tapDuration = tapDuration
        self.tapMovement = tapMovement
    }
}
