import GestureEngine
import HandPoseCore
import XCTest

/// Fixture-driven behavior tests — the engine's contract, expressed as
/// landmark recordings from `Fixtures/` and the exact intent sequences they
/// must produce.
final class GestureEngineFixtureTests: XCTestCase {
    private func consume(
        _ fixtureName: String, config: GestureConfig = GestureConfig()
    ) throws -> [PointerIntent] {
        var engine = GestureEngine(config: config)
        var intents: [PointerIntent] = []
        for frame in try FixtureLoader.frames(fixtureName) {
            intents += engine.consume(frame)
        }
        return intents
    }

    func testSmoothPinchTapClicksLeft() throws {
        // The spec's canonical example: a quick, stationary thumb–index
        // pinch is exactly engage → left click → disengage. The hand never
        // moves, so no moveBy intents appear at all.
        let intents = try consume("smooth_pinch_tap")
        XCTAssertEqual(intents, [.engaged, .click(.left), .disengaged])
    }

    func testJitteryHoldArmsDragWithoutFlicker() throws {
        // Pinch metric noise stays inside the hysteresis band for a full
        // second: the clutch must engage exactly once, arm a drag at
        // tapDuration (the hand is still), and release cleanly.
        let intents = try consume("jittery_pinch_hold")

        XCTAssertEqual(intents.count(of: .engaged), 1, "gate flickered: multiple engages")
        XCTAssertEqual(intents.count(of: .disengaged), 1, "gate flickered: multiple disengages")
        XCTAssertEqual(intents.count(of: .dragBegan), 1)
        XCTAssertEqual(intents.count(of: .dragEnded), 1)
        XCTAssertEqual(intents.clickCount, 0, "a held pinch must never click")
        XCTAssertEqual(intents.first, .engaged)
        XCTAssertEqual(intents.suffix(2), [.dragEnded, .disengaged])
    }

    func testHandLossMidDragReleasesTheDrag() throws {
        // Safety invariant, non-negotiable: when the hand vanishes mid-drag
        // the engine must emit dragEnded (button-up) before going idle.
        // A stuck drag must be impossible.
        let intents = try consume("hand_loss_mid_drag")

        XCTAssertEqual(intents.count(of: .dragBegan), 1)
        XCTAssertEqual(intents.count(of: .dragEnded), 1)
        XCTAssertEqual(intents.clickCount, 0)
        XCTAssertEqual(
            intents.suffix(2), [.dragEnded, .disengaged],
            "hand loss must end the drag first, then disengage"
        )

        let dragBeganIndex = try XCTUnwrap(intents.firstIndex(of: .dragBegan))
        let dragEndedIndex = try XCTUnwrap(intents.firstIndex(of: .dragEnded))
        XCTAssertLessThan(dragBeganIndex, dragEndedIndex)
        XCTAssertGreaterThan(
            Array(intents[dragBeganIndex..<dragEndedIndex]).moveCount, 0,
            "the fixture drags before the hand is lost"
        )
    }

    func testMiddlePinchScrollEmitsPhasedScrollStream() throws {
        // Thumb–middle pinch held then moved upward: a scrollBy stream with
        // negative dy, closed by exactly one scrollEnded on release. The
        // clutch never engages and nothing clicks.
        let intents = try consume("middle_pinch_scroll")

        XCTAssertGreaterThanOrEqual(intents.scrollCount, 20)
        XCTAssertEqual(intents.count(of: .scrollEnded), 1)
        XCTAssertEqual(intents.last, .scrollEnded)
        XCTAssertEqual(intents.count(of: .engaged), 0)
        XCTAssertEqual(intents.clickCount, 0)

        let allScrollsGoUp = intents.allSatisfy { intent in
            if case .scrollBy(_, let dy) = intent { return dy < 0 }
            return true
        }
        XCTAssertTrue(allScrollsGoUp, "the fixture's hand moves strictly upward")
    }

    // MARK: - Per-gesture enable toggles (settings)

    func testDisabledClickSuppressesTheTap() throws {
        var config = GestureConfig()
        config.clickEnabled = false
        let intents = try consume("smooth_pinch_tap", config: config)
        XCTAssertEqual(intents, [.engaged, .disengaged], "clutch still works, click is gone")
    }

    func testDisabledDragNeverArmsTheButton() throws {
        var config = GestureConfig()
        config.dragEnabled = false
        let intents = try consume("jittery_pinch_hold", config: config)
        XCTAssertEqual(intents.count(of: .dragBegan), 0)
        XCTAssertEqual(intents.count(of: .dragEnded), 0)
        XCTAssertEqual(intents.first, .engaged, "the clutch itself stays available")
        XCTAssertEqual(intents.last, .disengaged)
    }

    func testDisabledScrollMakesMiddlePinchHoldInert() throws {
        var config = GestureConfig()
        config.scrollEnabled = false
        let intents = try consume("middle_pinch_scroll", config: config)
        XCTAssertEqual(intents, [], "a long middle pinch with scroll disabled does nothing")
    }

    func testHandLossLandsInIdleAndTracksAgain() throws {
        var engine = GestureEngine()
        for frame in try FixtureLoader.frames("hand_loss_mid_drag") {
            _ = engine.consume(frame)
        }
        XCTAssertEqual(engine.state, .idle)

        // Re-acquisition: a fresh hand must be trackable again.
        var harness = EngineHarness()
        harness.engine = engine
        harness.feed(indexRatio: 1.0, frames: 3)
        XCTAssertEqual(harness.engine.state, .tracking)
        let batch = harness.feed(indexRatio: 0.15, frames: 2)
        XCTAssertTrue(batch.contains(.engaged), "engine must re-engage after recovery")
    }
}
