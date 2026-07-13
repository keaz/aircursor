import CoreGraphics
import Foundation
import MotionFilters
import XCTest

/// A rolling window that reports the spatial extent (bounding-box diagonal)
/// of a point's recent movement — large for any real sweep, small only when
/// the point is genuinely static.
final class MotionWindowTests: XCTestCase {
    func testEmptyWindowReportsNoExtent() {
        let window = MotionWindow(duration: 2.0)
        XCTAssertEqual(window.boundingExtent, 0)
    }

    func testExtentIsBoundingBoxDiagonal() {
        var window = MotionWindow(duration: 2.0)
        window.record(CGPoint(x: 0.4, y: 0.4), at: 0)
        window.record(CGPoint(x: 0.6, y: 0.6), at: 1.0)
        XCTAssertEqual(window.boundingExtent, hypot(0.2, 0.2), accuracy: 1e-9)
    }

    func testOldSamplesFallOutOfTheWindow() {
        var window = MotionWindow(duration: 1.0)
        window.record(CGPoint(x: 0.0, y: 0.0), at: 0)      // will expire
        window.record(CGPoint(x: 0.5, y: 0.5), at: 1.5)
        window.record(CGPoint(x: 0.52, y: 0.5), at: 2.0)
        // Only samples within [1.0, 2.0] count: a 0.02-wide box.
        XCTAssertEqual(window.boundingExtent, 0.02, accuracy: 1e-9)
    }

    func testStaticJitterStaysSmall() {
        var window = MotionWindow(duration: 2.0)
        var generator = SeededGenerator(seed: 3)
        for i in 0..<120 {
            let p = CGPoint(x: 0.5 + generator.jitter(0.004), y: 0.5 + generator.jitter(0.004))
            window.record(p, at: Double(i) / 60)
        }
        XCTAssertLessThan(window.boundingExtent, 0.02, "jitter covers only a tiny box")
    }

    func testOscillatingSweepReportsFullAmplitude() {
        // A back-and-forth drag returns near its start (net ≈ 0) but sweeps a
        // wide box — it must read as moving, not static.
        var window = MotionWindow(duration: 2.0)
        for i in 0...120 {
            let t = Double(i) / 60
            let x = 0.5 + 0.08 * sin(2 * .pi * t) // ±0.08 at 1 Hz
            window.record(CGPoint(x: x, y: 0.5), at: t)
        }
        XCTAssertGreaterThan(window.boundingExtent, 0.15, "a sweeping drag is not static")
    }

    func testResetClears() {
        var window = MotionWindow(duration: 2.0)
        window.record(CGPoint(x: 0.5, y: 0.5), at: 0)
        window.record(CGPoint(x: 0.9, y: 0.9), at: 1.0)
        window.reset()
        XCTAssertEqual(window.boundingExtent, 0)
    }
}
