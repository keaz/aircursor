import GestureEngine
import HandPoseCore
import XCTest

final class GestureConfigTests: XCTestCase {
    func testDefaultConfigMatchesSpec() {
        let config = GestureConfig()
        XCTAssertEqual(config.tapDuration, 0.25)
        XCTAssertEqual(config.tapMovement, 0.02)
        XCTAssertGreaterThan(
            config.pinchOpenThreshold, config.pinchCloseThreshold,
            "Hysteresis requires open > close"
        )
        XCTAssertEqual(config.movementJoint, .indexMCP)
        XCTAssertEqual(config.trackingLossGrace, 0.1)
        XCTAssertTrue(config.clickEnabled)
        XCTAssertTrue(config.dragEnabled)
        XCTAssertTrue(config.rightClickEnabled)
        XCTAssertTrue(config.scrollEnabled)
    }

    func testEngineStartsIdleAndIgnoresEmptyFrames() {
        var engine = GestureEngine()
        let intents = engine.consume(HandPoseFrame(joints: [:], timestamp: 0))
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(intents, [])
    }
}
