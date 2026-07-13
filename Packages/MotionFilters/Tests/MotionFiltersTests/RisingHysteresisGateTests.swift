import MotionFilters
import XCTest

/// Mirror-polarity gate for finger-extension detection: engages when the
/// value rises strictly above `engageThreshold`, releases when it falls
/// strictly below `releaseThreshold` (engage > release).
final class RisingHysteresisGateTests: XCTestCase {
    private func makeGate() -> RisingHysteresisGate {
        RisingHysteresisGate(engageThreshold: 1.15, releaseThreshold: 0.95)
    }

    func testStartsDisengaged() {
        XCTAssertFalse(makeGate().isEngaged)
    }

    func testEngagesStrictlyAboveEngageThreshold() {
        var gate = makeGate()
        XCTAssertFalse(gate.update(1.15), "exactly the engage threshold must not engage")
        XCTAssertTrue(gate.update(1.151))
    }

    func testReleasesStrictlyBelowReleaseThreshold() {
        var gate = makeGate()
        gate.update(1.4)
        XCTAssertTrue(gate.update(0.95), "exactly the release threshold must not release")
        XCTAssertFalse(gate.update(0.949))
    }

    func testBandHoldsCurrentState() {
        var gate = makeGate()
        for value in [1.0, 1.1, 0.96] {
            XCTAssertFalse(gate.update(value), "band value \(value) engaged a released gate")
        }
        gate.update(1.3)
        for value in [1.1, 0.96, 1.14] {
            XCTAssertTrue(gate.update(value), "band value \(value) released an engaged gate")
        }
    }

    func testNoFlickerInsideBandUnderNoise() {
        var gate = makeGate()
        var generator = SeededGenerator(seed: 99)
        gate.update(1.4)
        for _ in 0..<200 {
            let value = 0.96 + generator.unitDouble() * 0.18 // 0.96–1.14
            XCTAssertTrue(gate.update(value))
        }
        gate.update(0.5)
        for _ in 0..<200 {
            let value = 0.96 + generator.unitDouble() * 0.18
            XCTAssertFalse(gate.update(value))
        }
    }

    func testResetDisengages() {
        var gate = makeGate()
        gate.update(1.4)
        gate.reset()
        XCTAssertFalse(gate.isEngaged)
    }
}
