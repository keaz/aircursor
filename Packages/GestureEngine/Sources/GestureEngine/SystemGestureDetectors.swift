import CoreGraphics
import Foundation

/// Open-palm swipe strokes → Space switching. Fires when the wrist's
/// horizontal displacement over a trailing time window crosses the
/// threshold; a cooldown swallows the return stroke.
struct SwipeTracker: Sendable {
    private var history: [(point: CGPoint, time: TimeInterval)] = []
    private var cooldownUntil: TimeInterval = -.infinity

    mutating func reset() {
        history.removeAll(keepingCapacity: true)
    }

    mutating func update(
        wrist: CGPoint, at timestamp: TimeInterval, config: GestureConfig
    ) -> SystemAction? {
        history.append((wrist, timestamp))
        history.removeAll { timestamp - $0.time > config.swipeMaxDuration }

        guard timestamp >= cooldownUntil, let oldest = history.first else { return nil }
        let dx = wrist.x - oldest.point.x
        let dy = wrist.y - oldest.point.y
        guard abs(dx) >= config.swipeMinDisplacement,
              abs(dy) < abs(dx) * config.swipeMaxVerticalRatio
        else { return nil }

        cooldownUntil = timestamp + config.swipeCooldown
        history.removeAll(keepingCapacity: true)
        // Hand-space x tracks the user's own left/right.
        return dx > 0 ? .spaceRight : .spaceLeft
    }
}

/// Fist-to-open-palm bloom → Mission Control. Arms on a true fist (zero
/// extended fingers — pointing must never arm it), fires when all four
/// extend within the window with a stationary wrist.
struct BloomTracker: Sendable {
    private var armTime: TimeInterval?
    private var armWrist: CGPoint = .zero
    private var cooldownUntil: TimeInterval = -.infinity

    mutating func reset() {
        armTime = nil
        cooldownUntil = -.infinity
    }

    mutating func update(
        extendedCount: Int,
        wrist: CGPoint,
        at timestamp: TimeInterval,
        suppressedUntil: TimeInterval,
        config: GestureConfig
    ) -> SystemAction? {
        if extendedCount == 0 {
            armTime = timestamp
            armWrist = wrist
            return nil
        }
        guard extendedCount == 4, let armed = armTime else { return nil }
        armTime = nil // one evaluation per arm; re-arm requires a new fist

        let drift = hypot(wrist.x - armWrist.x, wrist.y - armWrist.y)
        guard timestamp - armed <= config.bloomWindow,
              drift <= config.bloomMaxWristDrift,
              timestamp >= cooldownUntil,
              timestamp >= suppressedUntil
        else { return nil }

        cooldownUntil = timestamp + config.bloomCooldown
        return .missionControl
    }
}
