import CoreGraphics
import Foundation
import HandPoseCore
import MotionFilters

/// The two pinches the engine recognizes.
public enum PinchKind: Equatable, Sendable {
    /// Thumb–index: clutch/move, click, drag.
    case index
    /// Thumb–middle: right click, scroll.
    case middle
}

/// Live pinch-metric values, exposed for the debug overlay.
public struct PinchMetrics: Equatable, Sendable {
    public var index: Double?
    public var middle: Double?

    public init(index: Double? = nil, middle: Double? = nil) {
        self.index = index
        self.middle = middle
    }
}

/// A synchronous, pure state machine turning hand-pose frames into pointer
/// intents. No OS framework imports; all state is value-typed.
///
/// Gesture semantics (interpreting the v1 spec):
/// - Index pinch closes → `.engaged`; hand movement flows as `.moveBy`.
/// - Quick, still release (< `tapDuration`, travel < `tapMovement`) →
///   `.click(.left)`.
/// - Travel beyond `tapMovement` commits the pinch to pure clutch-move: no
///   click on release, and no drag arming — a reposition must never press
///   the button.
/// - Holding still past `tapDuration` arms a drag (`.dragBegan`); movement
///   then drags; release (or hand loss) ends it.
/// - Middle pinch: quick still release → `.click(.right)`; holding or moving
///   promotes to scrolling (`.scrollBy` per frame). The clutch never engages.
///
/// Safety invariant (non-negotiable): any transition to `.idle` emits
/// `.dragEnded`/button-up intents first — a stuck drag must be impossible.
public struct GestureEngine: Sendable {
    public enum State: Equatable, Sendable {
        /// No hand, or confidence collapse outlasted the grace window.
        case idle
        /// Hand visible, clutch open.
        case tracking
        case pinched(kind: PinchKind, since: TimeInterval, origin: CGPoint)
        case dragging
        case scrolling
    }

    public private(set) var state: State = .idle
    public var config: GestureConfig
    /// Metric values from the newest frame, for the debug overlay.
    public private(set) var lastMetrics = PinchMetrics()

    private var indexGate: HysteresisGate
    private var middleGate: HysteresisGate
    /// Movement joint at the previous good frame; deltas are measured
    /// between consecutive good frames.
    private var lastMovementPoint: CGPoint?
    /// Greatest distance from the pinch origin seen during this pinch.
    private var maxTravelFromOrigin = 0.0
    /// An index pinch that traveled beyond `tapMovement`: locked to
    /// clutch-move, ineligible for click and drag.
    private var committedToMove = false
    /// Timestamp of the last frame with all required joints.
    private var lastGoodTimestamp: TimeInterval?

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
        self.indexGate = HysteresisGate(
            closeThreshold: config.pinchCloseThreshold,
            openThreshold: config.pinchOpenThreshold
        )
        self.middleGate = HysteresisGate(
            closeThreshold: config.pinchCloseThreshold,
            openThreshold: config.pinchOpenThreshold
        )
    }

    /// Consumes one frame and returns the intents it implies, in order.
    public mutating func consume(_ frame: HandPoseFrame) -> [PointerIntent] {
        let indexMetric = Self.pinchMetric(in: frame, tip: .indexTip)
        let middleMetric = Self.pinchMetric(in: frame, tip: .middleTip)
        lastMetrics = PinchMetrics(index: indexMetric, middle: middleMetric)

        // Baseline for any gesture work: the index metric and the movement
        // joint. States driven by the middle pinch also need its metric.
        let movementPoint = frame.joints[config.movementJoint]
        let middleRequired = isMiddlePinchActive
        guard let indexMetric,
              let movementPoint,
              !(middleRequired && middleMetric == nil)
        else {
            return handleDegradedFrame(at: frame.timestamp)
        }
        lastGoodTimestamp = frame.timestamp

        let delta = lastMovementPoint.map {
            CGVector(dx: movementPoint.x - $0.x, dy: movementPoint.y - $0.y)
        }
        defer { lastMovementPoint = movementPoint }

        switch state {
        case .idle:
            state = .tracking
            resetPinchBookkeeping()
            return []

        case .tracking:
            indexGate.update(indexMetric)
            if let middleMetric {
                middleGate.update(middleMetric)
            }

            if indexGate.isEngaged {
                middleGate.reset()
                beginPinch(.index, at: frame.timestamp, origin: movementPoint)
                return [.engaged]
            }
            if middleGate.isEngaged {
                indexGate.reset()
                beginPinch(.middle, at: frame.timestamp, origin: movementPoint)
                return []
            }
            return []

        case .pinched(let kind, let since, let origin):
            updateTravel(from: origin, to: movementPoint)
            let metric = kind == .index ? indexMetric : middleMetric
            let gateStillClosed = updateGate(for: kind, metric: metric)
            let isTap = frame.timestamp - since < config.tapDuration
                && maxTravelFromOrigin < config.tapMovement
                && !committedToMove

            guard gateStillClosed else {
                state = .tracking
                switch kind {
                case .index:
                    return isTap && config.clickEnabled
                        ? [.click(.left), .disengaged]
                        : [.disengaged]
                case .middle:
                    return isTap && config.rightClickEnabled ? [.click(.right)] : []
                }
            }

            if maxTravelFromOrigin >= config.tapMovement {
                committedToMove = true
            }

            switch kind {
            case .index:
                if config.dragEnabled, !committedToMove,
                   frame.timestamp - since >= config.tapDuration {
                    state = .dragging
                    return [.dragBegan]
                }
                return moveIntents(for: delta)

            case .middle:
                if config.scrollEnabled,
                   committedToMove || frame.timestamp - since >= config.tapDuration {
                    state = .scrolling
                    return scrollIntents(for: delta)
                }
                return []
            }

        case .dragging:
            guard updateGate(for: .index, metric: indexMetric) else {
                state = .tracking
                return [.dragEnded, .disengaged]
            }
            return moveIntents(for: delta)

        case .scrolling:
            guard updateGate(for: .middle, metric: middleMetric) else {
                state = .tracking
                return [.scrollEnded]
            }
            return scrollIntents(for: delta)
        }
    }

    /// Tears the engine down to `.idle` immediately (pipeline stopping,
    /// tracking toggled off). Returns the release intents the safety
    /// invariant demands — post them before discarding the pipeline.
    public mutating func reset() -> [PointerIntent] {
        transitionToIdle()
    }

    // MARK: - Degraded frames and the safety invariant

    private var isMiddlePinchActive: Bool {
        switch state {
        case .pinched(kind: .middle, _, _), .scrolling:
            return true
        case .idle, .tracking, .pinched, .dragging:
            return false
        }
    }

    private mutating func handleDegradedFrame(at timestamp: TimeInterval) -> [PointerIntent] {
        if state == .idle {
            return []
        }
        // Coast through brief Vision dropouts; deltas resume from the last
        // good frame after recovery.
        if let lastGood = lastGoodTimestamp,
           timestamp - lastGood <= config.trackingLossGrace {
            return []
        }
        return transitionToIdle()
    }

    /// The one exit ramp to `.idle`. Emits button-releasing intents first so
    /// a stuck drag is impossible by construction.
    private mutating func transitionToIdle() -> [PointerIntent] {
        let intents: [PointerIntent]
        switch state {
        case .dragging:
            intents = [.dragEnded, .disengaged]
        case .pinched(kind: .index, _, _):
            intents = [.disengaged]
        case .scrolling:
            intents = [.scrollEnded]
        case .idle, .tracking, .pinched(kind: .middle, _, _):
            intents = []
        }
        state = .idle
        indexGate.reset()
        middleGate.reset()
        resetPinchBookkeeping()
        lastMovementPoint = nil
        lastGoodTimestamp = nil
        return intents
    }

    // MARK: - Helpers

    private mutating func beginPinch(_ kind: PinchKind, at timestamp: TimeInterval, origin: CGPoint) {
        state = .pinched(kind: kind, since: timestamp, origin: origin)
        maxTravelFromOrigin = 0
        committedToMove = false
    }

    private mutating func resetPinchBookkeeping() {
        maxTravelFromOrigin = 0
        committedToMove = false
    }

    private mutating func updateTravel(from origin: CGPoint, to point: CGPoint) {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        maxTravelFromOrigin = max(maxTravelFromOrigin, (dx * dx + dy * dy).squareRoot())
    }

    /// Updates the gate for `kind` and returns whether it remains closed.
    /// The inactive gate stays reset while a pinch is in progress.
    private mutating func updateGate(for kind: PinchKind, metric: Double?) -> Bool {
        guard let metric else { return true } // metric gaps are grace-handled upstream
        switch kind {
        case .index:
            return indexGate.update(metric)
        case .middle:
            return middleGate.update(metric)
        }
    }

    private func moveIntents(for delta: CGVector?) -> [PointerIntent] {
        guard let delta, delta.dx != 0 || delta.dy != 0 else { return [] }
        return [.moveBy(dx: delta.dx, dy: delta.dy)]
    }

    private func scrollIntents(for delta: CGVector?) -> [PointerIntent] {
        guard let delta, delta.dx != 0 || delta.dy != 0 else { return [] }
        return [.scrollBy(dx: delta.dx, dy: delta.dy)]
    }

    /// Thumb-tip to `tip` distance, normalized by the wrist–middleMCP span
    /// so the metric is invariant to distance from the camera.
    private static func pinchMetric(in frame: HandPoseFrame, tip: HandJoint) -> Double? {
        guard let thumb = frame.joints[.thumbTip],
              let tipPoint = frame.joints[tip],
              let wrist = frame.joints[.wrist],
              let middleMCP = frame.joints[.middleMCP]
        else { return nil }

        let spanX = wrist.x - middleMCP.x
        let spanY = wrist.y - middleMCP.y
        let span = (spanX * spanX + spanY * spanY).squareRoot()
        guard span > .ulpOfOne else { return nil }

        let dx = thumb.x - tipPoint.x
        let dy = thumb.y - tipPoint.y
        return (dx * dx + dy * dy).squareRoot() / span
    }
}
