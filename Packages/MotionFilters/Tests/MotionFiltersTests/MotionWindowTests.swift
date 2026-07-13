import CoreGraphics
import MotionFilters
import XCTest

/// A rolling time window of points that reports how far the point has
/// actually travelled from where it was at the window's start — used to tell
/// a moving hand from a static (mis-tracked or held-still) one.
final class MotionWindowTests: XCTestCase {
    func testEmptyWindowReportsNoDisplacement() {
        let window = MotionWindow(duration: 2.0)
        XCTAssertEqual(window.netDisplacement, 0)
    }

    func testDisplacementIsDistanceFromOldestInWindow() {
        var window = MotionWindow(duration: 2.0)
        window.record(CGPoint(x: 0.5, y: 0.5), at: 0)
        window.record(CGPoint(x: 0.5, y: 0.5), at: 0.5)
        window.record(CGPoint(x: 0.6, y: 0.5), at: 1.0)
        XCTAssertEqual(window.netDisplacement, 0.1, accuracy: 1e-9)
    }

    func testOldSamplesFallOutOfTheWindow() {
        var window = MotionWindow(duration: 1.0)
        window.record(CGPoint(x: 0.0, y: 0.0), at: 0)      // will expire
        window.record(CGPoint(x: 0.5, y: 0.5), at: 1.5)    // window start now
        window.record(CGPoint(x: 0.52, y: 0.5), at: 2.0)
        // Only samples within [1.0, 2.0] count: from (0.5,0.5) to (0.52,0.5).
        XCTAssertEqual(window.netDisplacement, 0.02, accuracy: 1e-9)
    }

    func testStaticJitterStaysNearZero() {
        var window = MotionWindow(duration: 2.0)
        var generator = SeededGenerator(seed: 3)
        for i in 0..<120 {
            let p = CGPoint(x: 0.5 + generator.jitter(0.004), y: 0.5 + generator.jitter(0.004))
            window.record(p, at: Double(i) / 60)
        }
        XCTAssertLessThan(window.netDisplacement, 0.02, "jitter must not read as travel")
    }

    func testDenseWindowMeasuresDisplacementOverRoughlyTheDuration() {
        // At 60 fps the oldest retained sample sits ≈ duration back, so net
        // displacement reflects travel over ~the window.
        var window = MotionWindow(duration: 1.0)
        for i in 0...120 {
            let t = Double(i) / 60
            window.record(CGPoint(x: 0.5 + t * 0.1, y: 0.5), at: t) // 0.1/s rightward
        }
        // Over the trailing ~1s the point moved ~0.1.
        XCTAssertEqual(window.netDisplacement, 0.1, accuracy: 0.01)
    }

    func testResetClears() {
        var window = MotionWindow(duration: 2.0)
        window.record(CGPoint(x: 0.5, y: 0.5), at: 0)
        window.record(CGPoint(x: 0.9, y: 0.9), at: 1.0)
        window.reset()
        XCTAssertEqual(window.netDisplacement, 0)
    }
}
