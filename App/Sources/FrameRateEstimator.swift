import Foundation

/// Frames per second over a sliding one-second window of frame timestamps.
struct FrameRateEstimator {
    private var timestamps: [TimeInterval] = []

    mutating func record(_ timestamp: TimeInterval) -> Double {
        timestamps.append(timestamp)
        while let first = timestamps.first, timestamp - first > 1 {
            timestamps.removeFirst()
        }
        guard let first = timestamps.first, timestamp > first, timestamps.count > 1 else {
            return 0
        }
        return Double(timestamps.count - 1) / (timestamp - first)
    }
}
