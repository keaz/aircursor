import MotionFilters
import XCTest

final class HysteresisGateTests: XCTestCase {
    private func makeGate() -> HysteresisGate {
        HysteresisGate(closeThreshold: 0.35, openThreshold: 0.55)
    }

    func testStartsDisengaged() {
        XCTAssertFalse(makeGate().isEngaged)
    }

    func testEngagesStrictlyBelowCloseThreshold() {
        var gate = makeGate()
        XCTAssertFalse(gate.update(0.35), "exactly the close threshold must not engage")
        XCTAssertTrue(gate.update(0.349))
    }

    func testDoesNotEngageInsideBandWhenApproachingFromAbove() {
        var gate = makeGate()
        for value in [0.60, 0.54, 0.45, 0.36] {
            XCTAssertFalse(gate.update(value), "band value \(value) engaged a released gate")
        }
    }

    func testReleasesStrictlyAboveOpenThreshold() {
        var gate = makeGate()
        gate.update(0.30)
        XCTAssertTrue(gate.update(0.55), "exactly the open threshold must not release")
        XCTAssertFalse(gate.update(0.551))
    }

    func testNoFlickerWhileNoiseStaysInsideBand() {
        var gate = makeGate()
        var generator = SeededGenerator(seed: 7)

        gate.update(0.30)
        for _ in 0..<200 {
            let value = 0.36 + generator.unitDouble() * 0.18 // 0.36–0.54
            XCTAssertTrue(gate.update(value), "engaged gate flickered inside the band")
        }

        gate.update(0.60)
        for _ in 0..<200 {
            let value = 0.36 + generator.unitDouble() * 0.18
            XCTAssertFalse(gate.update(value), "released gate flickered inside the band")
        }
    }

    func testFullCycle() {
        var gate = makeGate()
        XCTAssertFalse(gate.update(0.80))
        XCTAssertTrue(gate.update(0.20))  // pinch closes
        XCTAssertTrue(gate.update(0.45))  // drifts inside band, still closed
        XCTAssertFalse(gate.update(0.70)) // opens
        XCTAssertFalse(gate.update(0.45)) // back in band, still open
        XCTAssertTrue(gate.update(0.10))  // closes again
    }

    func testResetDisengages() {
        var gate = makeGate()
        gate.update(0.10)
        XCTAssertTrue(gate.isEngaged)
        gate.reset()
        XCTAssertFalse(gate.isEngaged)
        XCTAssertFalse(gate.update(0.45), "band value engaged a reset gate")
    }
}
