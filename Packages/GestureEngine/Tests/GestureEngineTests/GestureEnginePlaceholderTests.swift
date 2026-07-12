import GestureEngine
import HandPoseCore
import XCTest

final class GestureEnginePlaceholderTests: XCTestCase {
    // M3 replaces this with fixture-driven tests asserting emitted intent
    // sequences (e.g. pinch_tap.json → [engaged, click(.left), disengaged]).
    func testDefaultConfigMatchesSpec() {
        let config = GestureConfig()
        XCTAssertEqual(config.tapDuration, 0.25)
        XCTAssertEqual(config.tapMovement, 0.02)
        XCTAssertGreaterThan(
            config.pinchOpenThreshold, config.pinchCloseThreshold,
            "Hysteresis requires open > close"
        )
    }

    func testEngineStartsIdle() {
        var engine = GestureEngine()
        let intents = engine.consume(HandPoseFrame(joints: [:], timestamp: 0))
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(intents, [])
    }
}
