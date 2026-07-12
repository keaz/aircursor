import CoreGraphics
import Foundation
import HandPoseCore

/// A synchronous, pure state machine turning hand-pose frames into pointer
/// intents. No OS framework imports; all state is value-typed.
///
/// M3 implements the transitions. Safety invariant (non-negotiable): any
/// transition to `.idle` emits `dragEnded`/button-up intents first — a stuck
/// drag must be impossible.
public struct GestureEngine: Sendable {
    public enum State: Equatable, Sendable {
        /// No hand, or confidence collapsed.
        case idle
        /// Hand visible, clutch open.
        case tracking
        case pinched(since: TimeInterval, origin: CGPoint)
        case dragging
        case scrolling
    }

    public private(set) var state: State = .idle
    public var config: GestureConfig

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    /// Consumes one frame and returns the intents it implies, in order.
    public mutating func consume(_ frame: HandPoseFrame) -> [PointerIntent] {
        // M3: pinch detection via HysteresisGate, tap-vs-drag promotion,
        // scroll, and the idle safety invariant.
        []
    }
}
