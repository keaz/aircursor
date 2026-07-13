import CoreGraphics
import GestureEngine
import HandPoseCore
import XCTest

/// Swipes (open-palm strokes → Spaces) and the Mission Control bloom
/// (fist → four fingers within a blink).
final class SystemGestureTests: XCTestCase {
    private let palm = TestHandV2.Fingers(index: true, middle: true, ring: true, little: true)

    // MARK: - Swipes

    func testFastPalmStrokeRightSwitchesSpaceRight() {
        var harness = EngineHarness()
        harness.feed(fingers: palm, frames: 2)
        for i in 1...4 {
            harness.feed(fingers: palm, center: CGPoint(x: 0.5 + Double(i) * 0.03, y: 0.55))
        }
        XCTAssertEqual(harness.intents.systemCount(.spaceRight), 1)
        XCTAssertEqual(harness.intents.systemCount(.spaceLeft), 0)
    }

    func testReturnStrokeInsideCooldownIsSwallowed() {
        var harness = EngineHarness()
        harness.feed(fingers: palm, frames: 2)
        for i in 1...4 {
            harness.feed(fingers: palm, center: CGPoint(x: 0.5 + Double(i) * 0.03, y: 0.55))
        }
        // Immediate return to start — fast leftward motion.
        for i in 1...4 {
            harness.feed(fingers: palm, center: CGPoint(x: 0.62 - Double(i) * 0.03, y: 0.55))
        }
        XCTAssertEqual(harness.intents.systemCount(.spaceRight), 1)
        XCTAssertEqual(harness.intents.systemCount(.spaceLeft), 0, "the return must not swipe back")
    }

    func testSecondStrokeAfterCooldownFires() {
        var harness = EngineHarness()
        harness.feed(fingers: palm, frames: 2)
        for i in 1...4 {
            harness.feed(fingers: palm, center: CGPoint(x: 0.5 + Double(i) * 0.03, y: 0.55))
        }
        harness.feed(fingers: palm, center: CGPoint(x: 0.62, y: 0.55), frames: 20) // > 0.6 s
        for i in 1...4 {
            harness.feed(fingers: palm, center: CGPoint(x: 0.62 + Double(i) * 0.03, y: 0.55))
        }
        XCTAssertEqual(harness.intents.systemCount(.spaceRight), 2)
    }

    func testVerticalPalmMotionDoesNotSwipe() {
        var harness = EngineHarness()
        harness.feed(fingers: palm, frames: 2)
        for i in 1...5 {
            harness.feed(fingers: palm, center: CGPoint(x: 0.5, y: 0.55 - Double(i) * 0.03))
        }
        XCTAssertEqual(harness.intents.systemCount(), 0)
    }

    func testPointingMotionNeverSwipes() {
        var harness = EngineHarness()
        harness.point(frames: 2)
        for i in 1...5 {
            harness.point(center: CGPoint(x: 0.5 + Double(i) * 0.04, y: 0.55))
        }
        XCTAssertEqual(harness.intents.systemCount(), 0, "swipes require the open palm")
    }

    func testDisabledSwipesAreInert() {
        var config = GestureConfig()
        config.swipesEnabled = false
        var harness = EngineHarness(config: config)
        harness.feed(fingers: palm, frames: 2)
        for i in 1...4 {
            harness.feed(fingers: palm, center: CGPoint(x: 0.5 + Double(i) * 0.03, y: 0.55))
        }
        XCTAssertEqual(harness.intents.systemCount(), 0)
    }

    // MARK: - Mission Control bloom

    func testFistToPalmBloomFiresMissionControl() {
        var harness = EngineHarness()
        harness.fist(frames: 3)
        harness.feed(fingers: palm, frames: 1)
        XCTAssertEqual(harness.intents.systemCount(.missionControl), 1)
    }

    func testBloomCooldownSuppressesImmediateRepeat() {
        var harness = EngineHarness()
        harness.fist(frames: 3)
        harness.feed(fingers: palm, frames: 2)
        harness.fist(frames: 2)
        harness.feed(fingers: palm, frames: 2) // still inside 1 s cooldown
        XCTAssertEqual(harness.intents.systemCount(.missionControl), 1)
    }

    func testSlowOpeningIsNotABloom() {
        var harness = EngineHarness()
        harness.fist(frames: 3)
        harness.feed(fingers: .init(index: true, middle: true), frames: 6) // 200 ms two-finger pause
        harness.feed(fingers: palm, frames: 1)
        XCTAssertEqual(harness.intents.systemCount(.missionControl), 0)
    }

    func testMovingBloomIsRejected() {
        var harness = EngineHarness()
        harness.fist(frames: 3)
        harness.feed(fingers: palm, center: CGPoint(x: 0.6, y: 0.55), frames: 1) // wrist leapt
        XCTAssertEqual(harness.intents.systemCount(.missionControl), 0)
    }

    func testBloomRightAfterButtonReleaseIsSuppressed() {
        var harness = EngineHarness()
        harness.point(frames: 3)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 4) // pressed
        harness.fist(frames: 2)  // release into fist
        harness.feed(fingers: palm, frames: 1) // fling the hand open
        XCTAssertEqual(
            harness.intents.systemCount(.missionControl), 0,
            "letting go of a drag by opening the hand must not fire Mission Control"
        )
    }

    func testDisabledMissionControlIsInert() {
        var config = GestureConfig()
        config.missionControlEnabled = false
        var harness = EngineHarness(config: config)
        harness.fist(frames: 3)
        harness.feed(fingers: palm, frames: 1)
        XCTAssertEqual(harness.intents.systemCount(), 0)
    }

    // MARK: - Recorded fixtures

    private func consume(_ fixtureName: String) throws -> [PointerIntent] {
        var engine = GestureEngine()
        var intents: [PointerIntent] = []
        for frame in try FixtureLoader.frames(fixtureName) {
            intents += engine.consume(frame)
        }
        return intents
    }

    func testSwipeRecordingsFireTheirDirections() throws {
        let left = try consume("recorded/swipe_left")
        XCTAssertGreaterThanOrEqual(left.systemCount(.spaceLeft), 1, "swipe_left must fire")
        XCTAssertGreaterThanOrEqual(
            left.systemCount(.spaceLeft), left.systemCount(.spaceRight),
            "left must dominate in swipe_left"
        )
        XCTAssertEqual(left.systemCount(.missionControl), 0)

        let right = try consume("recorded/swipe_right")
        XCTAssertGreaterThanOrEqual(right.systemCount(.spaceRight), 1, "swipe_right must fire")
        XCTAssertGreaterThanOrEqual(
            right.systemCount(.spaceRight), right.systemCount(.spaceLeft),
            "right must dominate in swipe_right"
        )
        XCTAssertEqual(right.systemCount(.missionControl), 0)
    }

    func testMissionControlRecordingBloomsWithoutSwipes() throws {
        let intents = try consume("recorded/mission_control")
        XCTAssertGreaterThanOrEqual(intents.systemCount(.missionControl), 2)
        XCTAssertEqual(intents.systemCount(.spaceLeft), 0)
        XCTAssertEqual(intents.systemCount(.spaceRight), 0)
    }

    func testOtherRecordingsFireNoSystemActions() throws {
        for fixture in ["recorded/mouse_move", "recorded/scroll_up", "recorded/scroll_down"] {
            let intents = try consume(fixture)
            XCTAssertEqual(
                intents.systemCount(.spaceLeft) + intents.systemCount(.spaceRight)
                    + intents.systemCount(.missionControl),
                0,
                fixture
            )
        }
    }
}
