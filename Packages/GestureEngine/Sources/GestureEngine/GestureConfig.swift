import Foundation
import HandPoseCore

/// Every gesture threshold lives here — no magic numbers inline in the
/// engine. Values marked "calibrated" come from the user's recorded
/// gestures in `Fixtures/recorded/`.
public struct GestureConfig: Equatable, Sendable {
    // MARK: Pinch (thumb–index over the wrist–middleMCP span)

    /// Pinch gate closes below this (calibrated: closed pinches read
    /// 0.06–0.2, open pointing stays ≥ 0.45).
    public var pinchCloseThreshold: Double
    /// ...and opens above this (> close, for hysteresis).
    public var pinchOpenThreshold: Double

    // MARK: Finger extension (tip–wrist over pip–wrist)

    /// Calibrated: extended fingers read 1.3–1.5.
    public var fingerExtendThreshold: Double
    /// Calibrated: curled fingers read 0.4–0.8.
    public var fingerRetractThreshold: Double

    // MARK: Two-finger tap (right click) and scroll commitment

    /// A scroll-pose visit no longer than this can be a right-click tap;
    /// it is also the deadline for movement to commit a scroll stroke.
    public var tapDuration: TimeInterval
    /// Normalized travel below which a scroll-pose visit is "still" (tap),
    /// and the dead zone before scroll deltas start flowing.
    public var tapMovement: Double
    /// Visits shorter than this are classifier blips, never taps.
    public var tapMinimumDuration: TimeInterval

    // MARK: Zoom ratchet (pinch armed from Neutral)

    /// Spread metric where the ratchet scale starts.
    public var zoomSpreadStart: Double
    /// One ⌘+ step per this much additional spread (calibrated: full
    /// spreads peak 1.43–1.65).
    public var zoomStepInterval: Double
    /// Consecutive frames of a deliberate pose (point/scroll/palm) needed
    /// to leave zooming — single-frame blips during spreads must not exit.
    public var zoomExitPoseFrames: Int

    // MARK: Swipes (open palm) and Mission Control bloom

    /// Minimum normalized horizontal displacement of a swipe stroke
    /// (calibrated: strokes reach 0.12–0.24).
    public var swipeMinDisplacement: Double
    /// The stroke must complete within this window.
    public var swipeMaxDuration: TimeInterval
    /// Ignore further swipes (and stroke returns) for this long after one.
    public var swipeCooldown: TimeInterval
    /// Fist → four extended fingers within this window is a bloom
    /// (calibrated: real blooms complete within ~1 frame).
    public var bloomWindow: TimeInterval
    /// The wrist must stay within this drift during a bloom.
    public var bloomMaxWristDrift: Double
    /// Ignore further blooms for this long after one fires.
    public var bloomCooldown: TimeInterval

    // MARK: Movement and tracking loss

    /// The joint whose translation drives cursor movement. MCPs track the
    /// palm and stay stable while fingers articulate.
    public var movementJoint: HandJoint
    /// How long the engine coasts through missing joints (Vision dropouts)
    /// before declaring the hand lost and going idle.
    public var trackingLossGrace: TimeInterval

    // MARK: Per-gesture enables (settings-controlled)

    /// Pointer movement is the core interaction and is always on.
    public var leftButtonEnabled: Bool
    public var rightButtonEnabled: Bool
    public var scrollEnabled: Bool
    public var zoomEnabled: Bool
    public var swipesEnabled: Bool
    public var missionControlEnabled: Bool

    public init(
        pinchCloseThreshold: Double = 0.35,
        pinchOpenThreshold: Double = 0.55,
        fingerExtendThreshold: Double = 1.15,
        fingerRetractThreshold: Double = 0.95,
        tapDuration: TimeInterval = 0.25,
        tapMovement: Double = 0.02,
        tapMinimumDuration: TimeInterval = 0.05,
        zoomSpreadStart: Double = 1.0,
        zoomStepInterval: Double = 0.15,
        zoomExitPoseFrames: Int = 3,
        swipeMinDisplacement: Double = 0.09,
        swipeMaxDuration: TimeInterval = 0.35,
        swipeCooldown: TimeInterval = 0.6,
        bloomWindow: TimeInterval = 0.13,
        bloomMaxWristDrift: Double = 0.05,
        bloomCooldown: TimeInterval = 1.0,
        movementJoint: HandJoint = .indexMCP,
        trackingLossGrace: TimeInterval = 0.1,
        leftButtonEnabled: Bool = true,
        rightButtonEnabled: Bool = true,
        scrollEnabled: Bool = true,
        zoomEnabled: Bool = true,
        swipesEnabled: Bool = true,
        missionControlEnabled: Bool = true
    ) {
        self.pinchCloseThreshold = pinchCloseThreshold
        self.pinchOpenThreshold = pinchOpenThreshold
        self.fingerExtendThreshold = fingerExtendThreshold
        self.fingerRetractThreshold = fingerRetractThreshold
        self.tapDuration = tapDuration
        self.tapMovement = tapMovement
        self.tapMinimumDuration = tapMinimumDuration
        self.zoomSpreadStart = zoomSpreadStart
        self.zoomStepInterval = zoomStepInterval
        self.zoomExitPoseFrames = zoomExitPoseFrames
        self.swipeMinDisplacement = swipeMinDisplacement
        self.swipeMaxDuration = swipeMaxDuration
        self.swipeCooldown = swipeCooldown
        self.bloomWindow = bloomWindow
        self.bloomMaxWristDrift = bloomMaxWristDrift
        self.bloomCooldown = bloomCooldown
        self.movementJoint = movementJoint
        self.trackingLossGrace = trackingLossGrace
        self.leftButtonEnabled = leftButtonEnabled
        self.rightButtonEnabled = rightButtonEnabled
        self.scrollEnabled = scrollEnabled
        self.zoomEnabled = zoomEnabled
        self.swipesEnabled = swipesEnabled
        self.missionControlEnabled = missionControlEnabled
    }
}
