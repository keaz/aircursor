import PointerControl
import XCTest

/// The gain curve is pure: g(v) = 1 + (maxGain − 1) · v² / (v² + halfSpeed²).
/// Slow hand → precision (gain 1), fast hand → travel (gain → maxGain).
final class VelocityGainCurveTests: XCTestCase {
    func testRestGainIsExactlyOne() {
        let curve = VelocityGainCurve(maxGain: 2, halfSpeed: 1)
        XCTAssertEqual(curve.gain(forSpeed: 0), 1)
    }

    func testHalfSpeedYieldsHalfTheBoost() {
        let curve = VelocityGainCurve(maxGain: 3, halfSpeed: 2)
        XCTAssertEqual(curve.gain(forSpeed: 2), 2, accuracy: 1e-12)
    }

    func testMonotoneNondecreasingAndBoundedByMaxGain() {
        let curve = VelocityGainCurve(maxGain: 2, halfSpeed: 1)
        var previous = 0.0
        for step in 0...100 {
            let gain = curve.gain(forSpeed: Double(step) * 0.2)
            XCTAssertGreaterThanOrEqual(gain, previous)
            XCTAssertLessThanOrEqual(gain, 2)
            previous = gain
        }
    }

    func testSaturatesTowardMaxGain() {
        let curve = VelocityGainCurve(maxGain: 2, halfSpeed: 1)
        XCTAssertGreaterThan(curve.gain(forSpeed: 100), 1.99)
    }

    func testFlatCurveWhenMaxGainIsOne() {
        let curve = VelocityGainCurve(maxGain: 1, halfSpeed: 1)
        for speed in [0.0, 0.5, 3.0, 50.0] {
            XCTAssertEqual(curve.gain(forSpeed: speed), 1)
        }
    }
}
