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
    /// A pinch only *arms* a press/zoom after the metric has risen above
    /// this — the hand must clearly open before it can pinch, like a button
    /// coming up before it goes down. This rejects a mis-tracked or resting
    /// hand that sits at a low metric without ever opening. Set to 0 to
    /// disable (any pinch arms).
    public var pinchArmThreshold: Double

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

    // MARK: Pose debounce (start slow, end fast)

    /// Consecutive frames an *active* pose (pinched, scroll) must persist
    /// before it starts a gesture — rejects 1–2 frame noise spikes.
    public var poseAdoptFrames: Int
    /// Consecutive frames a *calm* pose (point, neutral, palm) must persist
    /// before it ends a gesture. Kept below `poseAdoptFrames` so gestures
    /// end at least as fast as they start — the anti-stuck bias.
    public var poseReleaseFrames: Int

    // MARK: Watchdogs (guarantee a gesture can always end)

    /// Zoom's primary escape hatch: if the pinch metric stops moving for
    /// this long (no spread, no return stroke), the zoom ends. Set above a
    /// normal spread-and-hold (~0.9s) so it only fires when zoom is truly
    /// abandoned, not mid-gesture.
    public var zoomIdleTimeout: TimeInterval
    /// Hard backstop: a press held longer than this is force-released, so a
    /// mis-tracked sustained "pinch" can never stick the button down.
    public var maxPressDuration: TimeInterval
    /// Behavioral demotion: a press whose movement joint stays inside a box
    /// smaller than `stalePressMinTravel` across a window this long is
    /// released. A real drag — even a back-and-forth one — sweeps a wide box
    /// and a real click is brief, so only a held-still button (the signature
    /// of a mis-tracked background hand, or an accidental hold) trips it.
    /// This needs no way to identify the phantom — measurement showed no
    /// frame-local signal can — only that the press isn't sweeping.
    public var stalePressWindow: TimeInterval
    /// Bounding-box diagonal (movement-joint) below which a press is static.
    /// Measured separation: phantom holds cover ≤ ~0.055, real movement ≥
    /// ~0.085, so 0.05 catches phantom holds without touching real drags.
    public var stalePressMinTravel: Double
    /// Minimum pinch-metric change per frame that counts as zoom activity.
    /// A spread (rising) or a return stroke (falling) both move the metric;
    /// a hand held closed and still does not — so it times out.
    public var zoomActivityEpsilon: Double

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
    /// Fast strokes blur fingers below the extension gates for a frame or
    /// two; the swipe tracker survives this many consecutive non-palm
    /// frames before resetting.
    public var swipePoseDropoutFrames: Int
    /// A stroke's |dy| must stay under |dx| × this ratio. Real strokes are
    /// flat (measured ≤ 0.39) while diagonal wind-ups reach 0.69 — the
    /// wind-up before a flick must not fire the opposite swipe.
    public var swipeMaxVerticalRatio: Double
    /// Fist → four extended fingers within this window is a bloom
    /// (calibrated: real blooms complete within ~1 frame).
    public var bloomWindow: TimeInterval
    /// The wrist must stay within this drift during a bloom.
    public var bloomMaxWristDrift: Double
    /// Ignore further blooms for this long after one fires.
    public var bloomCooldown: TimeInterval
    /// Blooms are suppressed this long after a button release or a zoom
    /// exit — flinging the hand open to let go must not fire Mission
    /// Control.
    public var bloomSuppressAfterGesture: TimeInterval

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
        // Eager release: a press ends on a small separation (0.45) rather
        // than requiring the thumb and index to pull far apart. Widens the
        // gap that a relaxed hand can sit in without holding the button.
        pinchOpenThreshold: Double = 0.45,
        pinchArmThreshold: Double = 0.6,
        fingerExtendThreshold: Double = 1.15,
        fingerRetractThreshold: Double = 0.95,
        tapDuration: TimeInterval = 0.25,
        tapMovement: Double = 0.02,
        tapMinimumDuration: TimeInterval = 0.05,
        poseAdoptFrames: Int = 3,
        poseReleaseFrames: Int = 2,
        zoomIdleTimeout: TimeInterval = 1.2,
        maxPressDuration: TimeInterval = 8.0,
        stalePressWindow: TimeInterval = 2.0,
        stalePressMinTravel: Double = 0.05,
        zoomActivityEpsilon: Double = 0.04,
        zoomSpreadStart: Double = 1.0,
        zoomStepInterval: Double = 0.15,
        zoomExitPoseFrames: Int = 3,
        swipeMinDisplacement: Double = 0.09,
        swipeMaxDuration: TimeInterval = 0.35,
        swipeCooldown: TimeInterval = 0.6,
        swipePoseDropoutFrames: Int = 3,
        swipeMaxVerticalRatio: Double = 0.5,
        bloomWindow: TimeInterval = 0.13,
        bloomMaxWristDrift: Double = 0.05,
        bloomCooldown: TimeInterval = 1.0,
        bloomSuppressAfterGesture: TimeInterval = 0.3,
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
        self.pinchArmThreshold = pinchArmThreshold
        self.fingerExtendThreshold = fingerExtendThreshold
        self.fingerRetractThreshold = fingerRetractThreshold
        self.tapDuration = tapDuration
        self.tapMovement = tapMovement
        self.tapMinimumDuration = tapMinimumDuration
        self.poseAdoptFrames = poseAdoptFrames
        self.poseReleaseFrames = poseReleaseFrames
        self.zoomIdleTimeout = zoomIdleTimeout
        self.maxPressDuration = maxPressDuration
        self.stalePressWindow = stalePressWindow
        self.stalePressMinTravel = stalePressMinTravel
        self.zoomActivityEpsilon = zoomActivityEpsilon
        self.zoomSpreadStart = zoomSpreadStart
        self.zoomStepInterval = zoomStepInterval
        self.zoomExitPoseFrames = zoomExitPoseFrames
        self.swipeMinDisplacement = swipeMinDisplacement
        self.swipeMaxDuration = swipeMaxDuration
        self.swipeCooldown = swipeCooldown
        self.swipePoseDropoutFrames = swipePoseDropoutFrames
        self.swipeMaxVerticalRatio = swipeMaxVerticalRatio
        self.bloomWindow = bloomWindow
        self.bloomMaxWristDrift = bloomMaxWristDrift
        self.bloomCooldown = bloomCooldown
        self.bloomSuppressAfterGesture = bloomSuppressAfterGesture
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
