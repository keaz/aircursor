import CoreGraphics
import Foundation
import HandPoseCore
import MotionFilters

/// A synchronous, pure state machine turning hand-pose frames into pointer
/// intents. No OS framework imports; all state is value-typed.
///
/// v2 semantics ("invisible trackpad", calibrated against the recordings in
/// `Fixtures/recorded/`):
/// - Point pose moves the cursor; Neutral/openPalm freeze it.
/// - The pinch is the mouse button — but only when it forms **from the
///   Point pose** (the entry gate: relaxed hands pinch by accident during
///   scroll returns). Quick pinch = click, held pinch + movement = drag.
/// - A pinch formed from Neutral arms **zoom**: each spread ratchet step
///   emits a zoom action; re-closing re-arms. Zoom releases only through
///   unambiguous poses — a sustained open palm or two-finger pose (or
///   dropping the hand) — never through point/pinch, which spreads mimic.
/// - The Scroll pose (index+middle) scrolls once movement commits past a
///   dead zone; a short, still visit that returns to Point is a two-finger
///   tap → right click.
///
/// Safety invariant (non-negotiable): every exit from a pressed state —
/// pose change, hand loss, teardown — emits `released` first; a stuck
/// button is impossible by construction.
public struct GestureEngine: Sendable {
    public enum State: Equatable, Sendable {
        /// No hand, or confidence collapse outlasted the grace window.
        case idle
        /// Hand visible; relaxed/fist/undefined pose. Cursor frozen.
        case neutral
        /// Index-finger pointing: cursor moves.
        case pointing
        /// Pinch held as a mouse button (left in practice).
        case pressed(PointerButton)
        /// Two-finger pose: scrolling (or a pending tap).
        case scrolling
        /// Open palm: rest pose and swipe substrate. Cursor frozen.
        case palm
        /// Neutral-armed pinch: spread ratchets zoom steps.
        case zooming
    }

    public private(set) var state: State = .idle
    public var config: GestureConfig
    /// Newest classified pose and pinch metric, for the debug overlay.
    public private(set) var lastSnapshot: PoseSnapshot?

    private var classifier: PoseClassifier
    private var poseDebouncer = PoseDebouncer()
    private var lastMovementPoint: CGPoint?
    private var lastGoodTimestamp: TimeInterval?

    // Scrolling bookkeeping (tap-vs-stroke).
    private var scrollEntryTime: TimeInterval = 0
    private var scrollOrigin: CGPoint = .zero
    private var scrollTravel: Double = 0
    private var scrollCommitted = false
    /// Whether this scroll sequence actually emitted a `scrollBy`. The scroll
    /// phase is closed with `scrollEnded` iff this is true — independent of
    /// the live `scrollEnabled` flag, so disabling scrolling mid-stroke still
    /// closes an open phase and never fabricates one that never opened.
    private var scrollEmittedDelta = false

    // Zoom ratchet bookkeeping.
    private var zoomNextStepRatio = 0.0
    private var zoomExitStreak = 0

    // Watchdogs and the re-arm block that keeps a force-ended pinch gesture
    // from instantly re-triggering off the same sustained (mis-tracked)
    // pinch.
    private var pressEntryTime: TimeInterval = 0
    private var lastZoomActivityTime: TimeInterval = 0
    private var lastZoomMetric: Double = .nan
    private var pinchActionBlocked = false
    /// Recent travel of the movement joint, for stale-press demotion.
    private var movementWindow: MotionWindow
    /// A press/zoom can only start once the hand has clearly opened (the
    /// pinch metric rose above the arm threshold) since the last one — the
    /// closure edge that separates a deliberate pinch from a standing one.
    private var pinchArmed = false

    // System gesture detectors and their suppression window (blooms must
    // not fire while the hand is flung open to release something).
    private var swipeTracker = SwipeTracker()
    private var bloomTracker = BloomTracker()
    private var bloomSuppressedUntil: TimeInterval = -.infinity
    private var palmDropoutStreak = 0

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
        self.classifier = PoseClassifier(config: config)
        self.movementWindow = MotionWindow(duration: config.stalePressWindow)
    }

    /// Consumes one frame and returns the intents it implies, in order.
    public mutating func consume(_ frame: HandPoseFrame) -> [PointerIntent] {
        guard let snapshot = classifier.classify(frame),
              let movementPoint = frame.joints[config.movementJoint]
        else {
            return handleDegradedFrame(at: frame.timestamp)
        }
        lastSnapshot = snapshot
        lastGoodTimestamp = frame.timestamp

        let delta = lastMovementPoint.map {
            CGVector(dx: movementPoint.x - $0.x, dy: movementPoint.y - $0.y)
        }
        defer { lastMovementPoint = movementPoint }

        // Track recent movement-joint travel so the watchdog can demote a
        // press that has gone static.
        movementWindow.record(movementPoint, at: frame.timestamp)

        // Debounce the pose before the state machine reacts: active poses
        // must persist to start a gesture, calm poses end one quickly.
        let stablePose = poseDebouncer.update(
            snapshot.pose,
            adoptFrames: config.poseAdoptFrames,
            releaseFrames: config.poseReleaseFrames
        )
        // The re-arm block lifts as soon as the pinch has clearly opened.
        if stablePose != .pinched {
            pinchActionBlocked = false
        }
        // Arm a press/zoom once the hand has clearly opened (a real closure
        // edge). A hand that never opens — mis-tracked or resting at a low
        // metric — never arms, so it cannot start a phantom click.
        if snapshot.indexPinchMetric > config.pinchArmThreshold {
            pinchArmed = true
        }

        var intents: [PointerIntent] = []
        let previousState = state
        let target = watchdogOverride(at: frame.timestamp) ?? targetState(for: stablePose)
        let transitioned = target != state
        if transitioned {
            intents += transition(to: target, at: frame.timestamp, movementPoint: movementPoint, exitPose: stablePose)
        }
        intents += tick(
            snapshot: snapshot,
            delta: delta,
            movementPoint: movementPoint,
            at: frame.timestamp,
            suppressMotion: transitioned
        )

        // Releasing a button or leaving zoom usually flings the hand open;
        // hold blooms back for a beat.
        let released = intents.contains {
            if case .released = $0 { return true }
            return false
        }
        if released || (previousState == .zooming && state != .zooming) {
            bloomSuppressedUntil = frame.timestamp + config.bloomSuppressAfterGesture
        }

        if let wrist = frame.joints[.wrist] {
            if config.missionControlEnabled,
               let action = bloomTracker.update(
                   extendedCount: snapshot.fingers.extendedCount,
                   wrist: wrist,
                   at: frame.timestamp,
                   suppressedUntil: bloomSuppressedUntil,
                   config: config
               ) {
                intents.append(.system(action))
            }
            if state == .palm {
                palmDropoutStreak = 0
                if config.swipesEnabled,
                   let action = swipeTracker.update(wrist: wrist, at: frame.timestamp, config: config) {
                    intents.append(.system(action))
                }
            } else {
                // Strokes blur fingers out of the palm pose briefly; only a
                // sustained departure resets the stroke window.
                palmDropoutStreak += 1
                if palmDropoutStreak >= config.swipePoseDropoutFrames {
                    swipeTracker.reset()
                }
            }
        }
        return intents
    }

    /// Tears the engine down to `.idle` immediately (pipeline stopping).
    /// Returns the release intents the safety invariant demands.
    public mutating func reset() -> [PointerIntent] {
        let intents = idleExitIntents()
        state = .idle
        classifier.reset()
        clearTransientState()
        return intents
    }

    // MARK: - Target state resolution

    /// Watchdog-forced ends that guarantee a gesture can always terminate,
    /// independent of the pose signal. Returns a forced target, or nil to
    /// let the pose decide.
    private mutating func watchdogOverride(at timestamp: TimeInterval) -> State? {
        switch state {
        case .zooming where timestamp - lastZoomActivityTime > config.zoomIdleTimeout:
            // Spreading stopped: zoom is done. Block re-arm off the same
            // still-closed pinch until it opens.
            pinchActionBlocked = true
            return .neutral
        case .pressed where timestamp - pressEntryTime > config.maxPressDuration:
            // A press this long is almost certainly mis-tracked; let go.
            pinchActionBlocked = true
            return .pointing
        case .pressed where timestamp - pressEntryTime >= config.stalePressWindow
            && movementWindow.boundingExtent < config.stalePressMinTravel:
            // The movement joint has stayed inside a tiny box for the whole
            // window — not a real drag (which sweeps a box, even back and
            // forth) nor a brief click, so this is a stuck/phantom press.
            pinchActionBlocked = true
            return .pointing
        default:
            return nil
        }
    }

    private mutating func targetState(for pose: HandPose) -> State {
        // Zoom exits only through UNAMBIGUOUS poses. A wide spread reads as
        // Point (the index extends) and its re-close reads as pinch — the
        // recordings prove pose+motion heuristics cannot separate them from
        // real pointing/clicking, so point/pinch/neutral never leave zoom.
        // The user releases zoom by flashing an open palm or the two-finger
        // pose (or dropping the hand) — or the idle-timeout watchdog fires.
        if state == .zooming {
            switch pose {
            case .pinched, .neutral, .point:
                zoomExitStreak = 0
                return .zooming
            case .scroll, .openPalm:
                zoomExitStreak += 1
                if zoomExitStreak < config.zoomExitPoseFrames {
                    return .zooming
                }
            }
        }

        switch pose {
        case .point:
            return .pointing
        case .scroll:
            return .scrolling
        case .openPalm:
            return .palm
        case .neutral:
            return .neutral
        case .pinched:
            let pinchAllowed = pinchArmed && !pinchActionBlocked
            switch state {
            case .pointing:
                return config.leftButtonEnabled && pinchAllowed ? .pressed(.left) : .pointing
            case .pressed:
                return state
            case .neutral:
                return config.zoomEnabled && pinchAllowed ? .zooming : .neutral
            case .scrolling:
                // Return-phase noise: relaxed fingers brush the thumb.
                return .scrolling
            case .palm, .idle, .zooming:
                return .neutral
            }
        }
    }

    // MARK: - Transitions

    private mutating func transition(
        to target: State,
        at timestamp: TimeInterval,
        movementPoint: CGPoint,
        exitPose: HandPose
    ) -> [PointerIntent] {
        var intents: [PointerIntent] = []

        // 1. Leave the old state — buttons up and scroll phases closed first.
        switch state {
        case .pressed(let button):
            intents.append(.released(button))
        case .scrolling:
            intents += scrollExitIntents(at: timestamp, exitPose: exitPose)
        case .idle, .neutral, .pointing, .palm, .zooming:
            break
        }

        // 2. Clutch bookkeeping.
        let wasEngaged = Self.isEngagedState(state)
        let willEngage = Self.isEngagedState(target)
        if wasEngaged && !willEngage {
            intents.append(.disengaged)
        } else if !wasEngaged && willEngage {
            intents.append(.engaged)
        }

        // 3. Enter the new state.
        switch target {
        case .pressed(let button):
            pressEntryTime = timestamp
            pinchArmed = false // consumed; must re-open to click again
            intents.append(.pressed(button))
        case .scrolling:
            scrollEntryTime = timestamp
            scrollOrigin = movementPoint
            scrollTravel = 0
            scrollCommitted = false
            scrollEmittedDelta = false
        case .zooming:
            zoomNextStepRatio = config.zoomSpreadStart + config.zoomStepInterval
            zoomExitStreak = 0
            lastZoomActivityTime = timestamp
            lastZoomMetric = .nan
            pinchArmed = false
        case .idle, .neutral, .pointing, .palm:
            break
        }

        state = target
        return intents
    }

    private static func isEngagedState(_ state: State) -> Bool {
        switch state {
        case .pointing, .pressed:
            return true
        case .idle, .neutral, .scrolling, .palm, .zooming:
            return false
        }
    }

    /// Closing out a scroll visit: a committed stroke ends its phase; a
    /// short, still visit that exits into Point is a two-finger tap.
    private mutating func scrollExitIntents(
        at timestamp: TimeInterval, exitPose: HandPose
    ) -> [PointerIntent] {
        if scrollEmittedDelta {
            // A phase was opened; close it regardless of the live flag.
            return [.scrollEnded]
        }
        let dwell = timestamp - scrollEntryTime
        let isTap = config.rightButtonEnabled
            && exitPose == .point
            && dwell >= config.tapMinimumDuration
            && dwell <= config.tapDuration
            && scrollTravel < config.tapMovement
        return isTap ? [.pressed(.right), .released(.right)] : []
    }

    // MARK: - Per-frame behavior within a state

    private mutating func tick(
        snapshot: PoseSnapshot,
        delta: CGVector?,
        movementPoint: CGPoint,
        at timestamp: TimeInterval,
        suppressMotion: Bool
    ) -> [PointerIntent] {
        switch state {
        case .idle, .neutral, .palm:
            return []

        case .pointing, .pressed:
            // Transition frames anchor freshly — emitting the delta across
            // the pose change would leap the cursor.
            guard !suppressMotion,
                  let delta, delta.dx != 0 || delta.dy != 0
            else { return [] }
            return [.moveBy(dx: delta.dx, dy: delta.dy)]

        case .scrolling:
            guard !suppressMotion else { return [] }
            let dx = movementPoint.x - scrollOrigin.x
            let dy = movementPoint.y - scrollOrigin.y
            scrollTravel = max(scrollTravel, (dx * dx + dy * dy).squareRoot())
            if !scrollCommitted {
                // Dead zone: taps stay scroll-free; strokes commit quickly.
                if scrollTravel >= config.tapMovement
                    || timestamp - scrollEntryTime > config.tapDuration {
                    scrollCommitted = true
                }
                return []
            }
            guard config.scrollEnabled,
                  let delta, delta.dx != 0 || delta.dy != 0
            else { return [] }
            scrollEmittedDelta = true
            return [.scrollBy(dx: delta.dx, dy: delta.dy)]

        case .zooming:
            var intents: [PointerIntent] = []
            let metric = snapshot.indexPinchMetric
            var stepped = false
            while metric >= zoomNextStepRatio {
                intents.append(.system(.zoomStepIn))
                zoomNextStepRatio += config.zoomStepInterval
                stepped = true
            }
            if metric < config.pinchCloseThreshold {
                // Re-closed: re-arm the ratchet for the next spread stroke.
                zoomNextStepRatio = config.zoomSpreadStart + config.zoomStepInterval
            }
            // Activity = the metric is moving (spread rising or return stroke
            // falling) or a step fired. A hand held closed and still moves
            // the metric barely at all → the idle-timeout watchdog ends zoom.
            let moved = lastZoomMetric.isFinite
                && abs(metric - lastZoomMetric) > config.zoomActivityEpsilon
            if stepped || moved {
                lastZoomActivityTime = timestamp
            }
            lastZoomMetric = metric
            return intents
        }
    }

    // MARK: - Degraded frames and the safety invariant

    private mutating func handleDegradedFrame(at timestamp: TimeInterval) -> [PointerIntent] {
        if state == .idle {
            return []
        }
        if let lastGood = lastGoodTimestamp,
           timestamp - lastGood <= config.trackingLossGrace {
            return []
        }
        let intents = idleExitIntents()
        state = .idle
        classifier.reset()
        clearTransientState()
        return intents
    }

    /// The one set of exit emissions on the way to `.idle`: button up,
    /// scroll phase closed, clutch released — in that order.
    private func idleExitIntents() -> [PointerIntent] {
        var intents: [PointerIntent] = []
        switch state {
        case .pressed(let button):
            intents.append(.released(button))
            intents.append(.disengaged)
        case .pointing:
            intents.append(.disengaged)
        case .scrolling:
            if scrollEmittedDelta {
                intents.append(.scrollEnded)
            }
        case .idle, .neutral, .palm, .zooming:
            break
        }
        return intents
    }

    private mutating func clearTransientState() {
        lastMovementPoint = nil
        lastGoodTimestamp = nil
        lastSnapshot = nil
        scrollTravel = 0
        scrollCommitted = false
        scrollEmittedDelta = false
        zoomExitStreak = 0
        poseDebouncer.reset()
        pinchActionBlocked = false
        pinchArmed = false
        movementWindow.reset()
        swipeTracker.reset()
        bloomTracker.reset()
        bloomSuppressedUntil = -.infinity
    }
}
