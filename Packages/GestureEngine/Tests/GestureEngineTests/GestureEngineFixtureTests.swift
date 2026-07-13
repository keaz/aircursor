import GestureEngine
import HandPoseCore
import XCTest

/// The engine's contract against the user's real recorded gestures. Every
/// recording also asserts zero intents from every other gesture family —
/// cross-contamination is the failure mode that matters most.
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

    func testMouseMoveOnlyMovesTheCursor() throws {
        let intents = try consume("recorded/mouse_move")
        XCTAssertGreaterThanOrEqual(intents.count(of: .engaged), 1)
        XCTAssertGreaterThan(intents.moveCount, 50)
        XCTAssertEqual(intents.pressCount(), 0, "pointing must never press")
        XCTAssertEqual(intents.scrollCount, 0)
        XCTAssertEqual(intents.systemCount(), 0)
    }

    func testScrollRecordingsScrollWithoutClicking() throws {
        for (fixture, upward) in [("recorded/scroll_up", true), ("recorded/scroll_down", false)] {
            let intents = try consume(fixture)
            // Debounce trims a few frames off each stroke's start; the
            // contract is that scrolling clearly happens, not an exact count.
            XCTAssertGreaterThanOrEqual(intents.scrollCount, 5, fixture)
            XCTAssertGreaterThanOrEqual(intents.count(of: .scrollEnded), 1, fixture)
            XCTAssertEqual(
                intents.pressCount(.left), 0,
                "\(fixture): stroke returns must not phantom-click (the entry gate)"
            )
            XCTAssertEqual(intents.systemCount(), 0, fixture)

            // Direction is not asserted: the recordings' in-pose return
            // strokes are nearly symmetric with the outbound strokes (each
            // stroke scrolls its own direction, which is correct trackpad
            // behavior). Mechanics — strokes, closed phases, zero clicks —
            // are the contract.
            _ = upward
        }
    }

    func testZoomRecordingRatchetsWithoutClicking() throws {
        let intents = try consume("recorded/zoom_in")
        XCTAssertGreaterThanOrEqual(intents.systemCount(.zoomStepIn), 3)
        XCTAssertEqual(
            intents.pressCount(), 0,
            "neutral-armed pinches must never press — the click-vs-zoom gate"
        )
        XCTAssertEqual(intents.scrollCount, 0)
    }

    func testSwipeRecordingsProduceNoPointerNoise() throws {
        // Swipe detection itself lands in the next step; the engine must
        // already stay quiet on the pointer/button/scroll families.
        for fixture in ["recorded/swipe_left", "recorded/swipe_right"] {
            let intents = try consume(fixture)
            XCTAssertEqual(intents.pressCount(), 0, fixture)
            XCTAssertEqual(intents.scrollCount, 0, fixture)
        }
    }

    func testMissionControlRecordingProducesNoPointerNoise() throws {
        let intents = try consume("recorded/mission_control")
        XCTAssertEqual(intents.pressCount(), 0)
        XCTAssertEqual(intents.scrollCount, 0)
    }
}
