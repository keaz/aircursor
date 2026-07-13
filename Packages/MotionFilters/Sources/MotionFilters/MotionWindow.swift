import CoreGraphics
import Foundation

/// A rolling time window of positions that reports the spatial *extent* of
/// the point's movement — the diagonal of the bounding box it covered over
/// the window. Used to distinguish a moving hand from a static one: a
/// mis-tracked background "hand" or a held-still press stays in a tiny box,
/// while a real gesture — including a back-and-forth drag that returns near
/// its start — sweeps a large box.
///
/// Extent, not net (endpoint) displacement: an oscillating drag has ~zero
/// net displacement yet is clearly moving. Extent, not path length: jitter
/// inflates path length, so a static hand would look busy.
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

    /// Diagonal of the axis-aligned bounding box of the in-window samples.
    /// Small for jitter or a held-still point; large for any real sweep,
    /// oscillating or one-way.
    public var boundingExtent: Double {
        guard let first = samples.first else { return 0 }
        var minX = first.point.x, maxX = first.point.x
        var minY = first.point.y, maxY = first.point.y
        for sample in samples.dropFirst() {
            minX = min(minX, sample.point.x); maxX = max(maxX, sample.point.x)
            minY = min(minY, sample.point.y); maxY = max(maxY, sample.point.y)
        }
        return hypot(maxX - minX, maxY - minY)
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}
