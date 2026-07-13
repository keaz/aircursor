import CoreGraphics
import Foundation

/// A rolling time window of positions that reports how far the point has
/// actually travelled from where it was at the start of the window
/// (net displacement, not jittery path length). Used to distinguish a moving
/// hand from a static one — a mis-tracked background "hand" or a held-still
/// press barely moves, while a real gesture travels.
public struct MotionWindow: Sendable {
    private var samples: [(point: CGPoint, time: TimeInterval)] = []
    /// How far back the window reaches.
    public let duration: TimeInterval

    public init(duration: TimeInterval) {
        precondition(duration > 0, "duration must be positive")
        self.duration = duration
    }

    /// Adds a sample and drops any older than `duration` before the newest.
    public mutating func record(_ point: CGPoint, at time: TimeInterval) {
        samples.append((point, time))
        while let first = samples.first, time - first.time > duration {
            samples.removeFirst()
        }
    }

    /// Distance from the oldest in-window sample to the newest. Oscillating
    /// jitter returns near zero; sustained travel returns the real distance.
    public var netDisplacement: Double {
        guard let oldest = samples.first, let newest = samples.last else { return 0 }
        return hypot(newest.point.x - oldest.point.x, newest.point.y - oldest.point.y)
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}
