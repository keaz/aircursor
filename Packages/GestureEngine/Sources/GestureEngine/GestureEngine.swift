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
    private var lastMovementPoint: CGPoint?
    private var lastGoodTimestamp: TimeInterval?

    // Scrolling bookkeeping (tap-vs-stroke).
    private var scrollEntryTime: TimeInterval = 0
    private var scrollOrigin: CGPoint = .zero
    private var scrollTravel: Double = 0
    private var scrollCommitted = false

    // Zoom ratchet bookkeeping.
    private var zoomNextStepRatio = 0.0
    private var zoomExitStreak = 0

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
        self.classifier = PoseClassifier(config: config)
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

        var intents: [PointerIntent] = []
        let target = targetState(for: snapshot)
        let transitioned = target != state
        if transitioned {
            intents += transition(to: target, at: frame.timestamp, movementPoint: movementPoint, exitPose: snapshot.pose)
        }
        intents += tick(
            snapshot: snapshot,
            delta: delta,
            movementPoint: movementPoint,
            at: frame.timestamp,
            suppressMotion: transitioned
        )
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

    private mutating func targetState(for snapshot: PoseSnapshot) -> State {
        // Zoom exits only through UNAMBIGUOUS poses. A wide spread reads as
        // Point (the index extends) and its re-close reads as pinch — the
        // recordings prove pose+motion heuristics cannot separate them from
        // real pointing/clicking, so point/pinch/neutral never leave zoom.
        // The user releases zoom by flashing an open palm or the two-finger
        // pose (or dropping the hand).
        if state == .zooming {
            switch snapshot.pose {
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

        switch snapshot.pose {
        case .point:
            return .pointing
        case .scroll:
            return .scrolling
        case .openPalm:
            return .palm
        case .neutral:
            return .neutral
        case .pinched:
            switch state {
            case .pointing:
                return config.leftButtonEnabled ? .pressed(.left) : .pointing
            case .pressed:
                return state
            case .neutral:
                return config.zoomEnabled ? .zooming : .neutral
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
            intents.append(.pressed(button))
        case .scrolling:
            scrollEntryTime = timestamp
            scrollOrigin = movementPoint
            scrollTravel = 0
            scrollCommitted = false
        case .zooming:
            zoomNextStepRatio = config.zoomSpreadStart + config.zoomStepInterval
            zoomExitStreak = 0
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
        if scrollCommitted {
            return config.scrollEnabled ? [.scrollEnded] : []
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
            return [.scrollBy(dx: delta.dx, dy: delta.dy)]

        case .zooming:
            var intents: [PointerIntent] = []
            let metric = snapshot.indexPinchMetric
            while metric >= zoomNextStepRatio {
                intents.append(.system(.zoomStepIn))
                zoomNextStepRatio += config.zoomStepInterval
            }
            if metric < config.pinchCloseThreshold {
                // Re-closed: re-arm the ratchet for the next spread stroke.
                zoomNextStepRatio = config.zoomSpreadStart + config.zoomStepInterval
            }
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
            if scrollCommitted && config.scrollEnabled {
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
        zoomExitStreak = 0
    }
}
