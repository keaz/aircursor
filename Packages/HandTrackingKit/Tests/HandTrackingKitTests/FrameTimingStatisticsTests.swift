import HandPoseCore
import XCTest

final class FrameTimingStatisticsTests: XCTestCase {
    /// Steady 30 fps: rate ≈ 30, all gap percentiles at ~1/30, no long gaps.
    func testSteadyStreamReportsRateAndTightGaps() throws {
        var stats = FrameTimingStatistics(window: 5)
        for i in 0...90 { // 3 seconds at 30 fps
            stats.record(Double(i) / 30)
        }
        let snap = try XCTUnwrap(stats.snapshot())
        XCTAssertEqual(snap.framesPerSecond, 30, accuracy: 0.1)
        XCTAssertEqual(snap.medianGap, 1.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(snap.p95Gap, 1.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(snap.maxGap, 1.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(snap.longGapCount, 0)
        XCTAssertEqual(snap.frameCount, 91)
    }

    /// One dropped frame (a single 2× gap) must show up in maxGap and the
    /// long-gap count while barely moving the median.
    func testSingleDroppedFrameIsCountedAsLongGap() throws {
        var stats = FrameTimingStatistics(window: 5)
        var t = 0.0
        for i in 0..<60 {
            t += (i == 30) ? 2.0 / 30 : 1.0 / 30 // one skipped frame
            stats.record(t)
        }
        let snap = try XCTUnwrap(stats.snapshot())
        XCTAssertEqual(snap.medianGap, 1.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(snap.maxGap, 2.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(snap.longGapCount, 1)
    }

    /// Samples older than the window are pruned: after 10 s of 60 fps then
    /// 5 s of 30 fps with a 5 s window, only the 30 fps regime remains.
    func testWindowPrunesOldRegime() throws {
        var stats = FrameTimingStatistics(window: 5)
        var t = 0.0
        for _ in 0..<600 { t += 1.0 / 60; stats.record(t) } // 10 s @ 60
        for _ in 0..<150 { t += 1.0 / 30; stats.record(t) } // 5 s @ 30
        let snap = try XCTUnwrap(stats.snapshot())
        XCTAssertEqual(snap.framesPerSecond, 30, accuracy: 0.5)
        XCTAssertEqual(snap.medianGap, 1.0 / 30, accuracy: 1e-9)
    }

    /// Not enough data → no snapshot rather than junk numbers.
    func testNeedsAtLeastTwoSamples() {
        var stats = FrameTimingStatistics(window: 5)
        XCTAssertNil(stats.snapshot())
        stats.record(1.0)
        XCTAssertNil(stats.snapshot())
        stats.record(1.5)
        XCTAssertNotNil(stats.snapshot())
    }

    /// Duplicate timestamps (zero median) must not divide by zero or count
    /// everything as a long gap.
    func testDuplicateTimestampsAreSafe() throws {
        var stats = FrameTimingStatistics(window: 5)
        stats.record(1.0)
        stats.record(1.0)
        stats.record(1.1)
        let snap = try XCTUnwrap(stats.snapshot())
        XCTAssertEqual(snap.longGapCount, 0)
        XCTAssertEqual(snap.maxGap, 0.1, accuracy: 1e-9)
    }
}
