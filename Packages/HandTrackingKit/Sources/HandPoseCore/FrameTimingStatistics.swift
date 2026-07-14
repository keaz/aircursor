import Foundation

/// Rolling diagnostics over frame timestamps: delivered rate plus the
/// inter-frame gap distribution.
///
/// Answers "what frame rate is the pipeline *actually* seeing, and how stable
/// is it?" — which matters because the gesture engine's debounce thresholds
/// are frame counts: a camera that clamps 60 → 30 fps, or drops frames under
/// inference load, silently changes their real-time meaning. Pure value type;
/// feed it the same timestamps the engine consumes.
public struct FrameTimingStatistics: Sendable {
    public struct Snapshot: Equatable, Sendable {
        /// Delivered frames per second over the window.
        public let framesPerSecond: Double
        /// Median inter-frame gap, seconds.
        public let medianGap: TimeInterval
        /// 95th-percentile inter-frame gap, seconds.
        public let p95Gap: TimeInterval
        /// Worst inter-frame gap in the window, seconds.
        public let maxGap: TimeInterval
        /// Gaps longer than 1.5× the median — a proxy for dropped/late frames.
        public let longGapCount: Int
        /// Timestamps currently in the window.
        public let frameCount: Int
    }

    private var timestamps: [TimeInterval] = []
    private let window: TimeInterval

    /// - Parameter window: how many seconds of history the statistics cover.
    public init(window: TimeInterval = 5) {
        precondition(window > 0)
        self.window = window
    }

    public mutating func record(_ timestamp: TimeInterval) {
        timestamps.append(timestamp)
        while let first = timestamps.first, timestamp - first > window {
            timestamps.removeFirst()
        }
    }

    /// Current statistics, or nil until two samples exist. O(n log n) in the
    /// window size (≤ a few hundred samples) — fine to call per frame.
    public func snapshot() -> Snapshot? {
        guard timestamps.count >= 2,
              let first = timestamps.first, let last = timestamps.last, last > first
        else { return nil }

        var gaps: [TimeInterval] = []
        gaps.reserveCapacity(timestamps.count - 1)
        for i in 1..<timestamps.count {
            gaps.append(timestamps[i] - timestamps[i - 1])
        }
        let sorted = gaps.sorted()
        let median = percentile(sorted, 0.5)
        return Snapshot(
            framesPerSecond: Double(timestamps.count - 1) / (last - first),
            medianGap: median,
            p95Gap: percentile(sorted, 0.95),
            maxGap: sorted[sorted.count - 1],
            longGapCount: median > 0 ? gaps.filter { $0 > 1.5 * median }.count : 0,
            frameCount: timestamps.count
        )
    }

    private func percentile(_ sorted: [TimeInterval], _ p: Double) -> TimeInterval {
        sorted[Int((Double(sorted.count - 1) * p).rounded())]
    }
}
