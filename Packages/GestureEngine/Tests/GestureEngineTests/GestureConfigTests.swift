import GestureEngine
import HandPoseCore
import XCTest

final class GestureConfigTests: XCTestCase {
    func testDefaultConfigMatchesSpec() {
        let config = GestureConfig()
        XCTAssertGreaterThan(
            config.pinchOpenThreshold, config.pinchCloseThreshold,
            "Hysteresis requires open > close"
        )
        XCTAssertGreaterThan(
            config.fingerExtendThreshold, config.fingerRetractThreshold,
            "Extension hysteresis requires extend > retract"
        )
        XCTAssertEqual(config.movementJoint, .indexMCP)
        XCTAssertEqual(config.trackingLossGrace, 0.1)
        // Two-finger tap bounds.
        XCTAssertEqual(config.tapDuration, 0.25)
        XCTAssertEqual(config.tapMovement, 0.02)
        // Zoom ratchet.
        XCTAssertEqual(config.zoomSpreadStart, 1.0)
        XCTAssertEqual(config.zoomStepInterval, 0.15)
        // Everything ships enabled.
        XCTAssertTrue(config.leftButtonEnabled)
        XCTAssertTrue(config.rightButtonEnabled)
        XCTAssertTrue(config.scrollEnabled)
        XCTAssertTrue(config.zoomEnabled)
        XCTAssertTrue(config.swipesEnabled)
        XCTAssertTrue(config.missionControlEnabled)
    }

    func testEngineStartsIdleAndIgnoresEmptyFrames() {
        var engine = GestureEngine()
        let intents = engine.consume(HandPoseFrame(joints: [:], timestamp: 0))
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(intents, [])
    }
}
