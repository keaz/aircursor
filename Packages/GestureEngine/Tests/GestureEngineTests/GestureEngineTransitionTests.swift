import CoreGraphics
import GestureEngine
import HandPoseCore
import XCTest

/// Programmatic transition coverage: every branch of the tap / clutch-move /
/// drag / right-tap / scroll decision tree, plus grace-period behavior.
final class GestureEngineTransitionTests: XCTestCase {
    // MARK: - Clutch move vs click vs drag

    func testMovingBeyondTapMovementCommitsToClutchMove() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 0.15, frames: 2)

        // Sweep 0.05 to the right — far past tapMovement (0.02).
        for i in 1...10 {
            harness.feed(
                indexRatio: 0.15,
                center: CGPoint(x: 0.5 + Double(i) * 0.005, y: 0.55)
            )
        }
        // Hold still for well over tapDuration: a committed move must NOT
        // retro-arm a drag (that would press the button mid-positioning).
        harness.feed(
            indexRatio: 0.15,
            center: CGPoint(x: 0.55, y: 0.55),
            frames: 30
        )
        harness.feed(indexRatio: 1.0, frames: 2)

        XCTAssertEqual(harness.intents.count(of: .engaged), 1)
        XCTAssertEqual(harness.intents.count(of: .dragBegan), 0, "moving commits to move, never drag")
        XCTAssertEqual(harness.intents.clickCount, 0, "a moved pinch must not click on release")
        XCTAssertGreaterThan(harness.intents.moveCount, 5)
        XCTAssertEqual(harness.intents.last, .disengaged)
    }

    func testMoveDeltasMatchHandTravel() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 0.15, frames: 1)

        let batch = harness.feed(indexRatio: 0.15, center: CGPoint(x: 0.51, y: 0.54))
        guard case .moveBy(let dx, let dy)? = batch.first, batch.count == 1 else {
            return XCTFail("expected a single moveBy, got \(batch)")
        }
        XCTAssertEqual(dx, 0.01, accuracy: 1e-9)
        XCTAssertEqual(dy, -0.01, accuracy: 1e-9)
    }

    func testStationaryPinchEmitsNoMoves() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 0.15, frames: 5)
        XCTAssertEqual(harness.intents.moveCount, 0)
    }

    func testStillHoldArmsDragAndMovesDragTheButton() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 0.15, frames: 17) // ≈267 ms still — arms the drag

        XCTAssertEqual(harness.intents.count(of: .dragBegan), 1)
        XCTAssertEqual(harness.engine.state, .dragging)

        for i in 1...5 {
            harness.feed(
                indexRatio: 0.15,
                center: CGPoint(x: 0.5 + Double(i) * 0.005, y: 0.55)
            )
        }
        harness.feed(indexRatio: 1.0, frames: 1)

        XCTAssertGreaterThanOrEqual(harness.intents.moveCount, 5, "drag moves flow as moveBy")
        XCTAssertEqual(harness.intents.suffix(2), [.dragEnded, .disengaged])
        XCTAssertEqual(harness.intents.clickCount, 0)
    }

    func testTapMovementBoundary() {
        // 0.019 of travel still clicks; 0.021 commits to move.
        var clicking = EngineHarness()
        clicking.feed(indexRatio: 1.0, frames: 3)
        clicking.feed(indexRatio: 0.15, frames: 1)
        clicking.feed(indexRatio: 0.15, center: CGPoint(x: 0.519, y: 0.55))
        clicking.feed(indexRatio: 1.0, frames: 1)
        XCTAssertEqual(clicking.intents.clickCount, 1)

        var moving = EngineHarness()
        moving.feed(indexRatio: 1.0, frames: 3)
        moving.feed(indexRatio: 0.15, frames: 1)
        moving.feed(indexRatio: 0.15, center: CGPoint(x: 0.521, y: 0.55))
        moving.feed(indexRatio: 1.0, frames: 1)
        XCTAssertEqual(moving.intents.clickCount, 0)
    }

    // MARK: - Middle pinch: right click and scroll

    func testMiddlePinchTapRightClicks() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 1.0, middleRatio: 0.15, frames: 5)
        harness.feed(indexRatio: 1.0, middleRatio: 1.1, frames: 2)

        XCTAssertEqual(harness.intents, [.click(.right)], "a right tap is only a click — no clutch")
    }

    func testMiddlePinchHoldAndVerticalMoveScrolls() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 1.0, middleRatio: 0.15, frames: 3)

        for i in 1...10 {
            harness.feed(
                indexRatio: 1.0,
                middleRatio: 0.15,
                center: CGPoint(x: 0.5, y: 0.55 - Double(i) * 0.005)
            )
        }
        XCTAssertEqual(harness.engine.state, .scrolling)
        harness.feed(indexRatio: 1.0, middleRatio: 1.1, frames: 2)

        XCTAssertGreaterThanOrEqual(harness.intents.scrollCount, 5)
        XCTAssertEqual(harness.intents.clickCount, 0)
        XCTAssertEqual(harness.intents.count(of: .engaged), 0, "scroll never engages the clutch")
        XCTAssertEqual(harness.intents.last, .scrollEnded, "release must close the scroll phase")
        XCTAssertEqual(harness.engine.state, .tracking)

        let hasUpwardScroll = harness.intents.contains { intent in
            if case .scrollBy(_, let dy) = intent { return dy < 0 }
            return false
        }
        XCTAssertTrue(hasUpwardScroll)
    }

    func testHandLossMidScrollEndsTheScrollPhase() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 1.0, middleRatio: 0.15, frames: 17)
        XCTAssertEqual(harness.engine.state, .scrolling)

        let lostBatch = harness.feedLost(frames: 10)
        XCTAssertEqual(lostBatch, [.scrollEnded], "apps need the phase closed on hand loss")
        XCTAssertEqual(harness.engine.state, .idle)
    }

    func testResetMidScrollEndsTheScrollPhase() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 1.0, middleRatio: 0.15, frames: 17)
        XCTAssertEqual(harness.engine.state, .scrolling)
        XCTAssertEqual(harness.engine.reset(), [.scrollEnded])
    }

    func testDisabledRightClickSuppressesMiddleTap() {
        var config = GestureConfig()
        config.rightClickEnabled = false
        var harness = EngineHarness(config: config)
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 1.0, middleRatio: 0.15, frames: 5)
        harness.feed(indexRatio: 1.0, middleRatio: 1.1, frames: 2)
        XCTAssertEqual(harness.intents, [])
    }

    func testIndexPinchWinsWhenBothPinchesClose() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 0.15, middleRatio: 0.15, frames: 4)
        harness.feed(indexRatio: 1.0, middleRatio: 1.1, frames: 2)

        XCTAssertEqual(harness.intents, [.engaged, .click(.left), .disengaged])
    }

    // MARK: - Tracking loss and grace

    func testBriefJointDropoutInsideGraceKeepsTheDrag() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 0.15, frames: 17) // drag armed
        XCTAssertEqual(harness.engine.state, .dragging)

        let lostBatch = harness.feedLost(frames: 3) // 50 ms < 100 ms grace
        XCTAssertEqual(lostBatch, [], "inside the grace window nothing is emitted")
        XCTAssertEqual(harness.engine.state, .dragging, "grace must preserve the drag")

        harness.feed(indexRatio: 0.15, center: CGPoint(x: 0.52, y: 0.55))
        XCTAssertEqual(harness.intents.count(of: .dragEnded), 0)
        XCTAssertGreaterThan(harness.intents.moveCount, 0, "movement resumes after recovery")
    }

    func testLossBeyondGraceMidDragReleasesButtonBeforeIdle() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 0.15, frames: 17)
        XCTAssertEqual(harness.engine.state, .dragging)

        let lostBatch = harness.feedLost(frames: 10) // ≈167 ms > grace
        XCTAssertEqual(lostBatch, [.dragEnded, .disengaged])
        XCTAssertEqual(harness.engine.state, .idle)
    }

    func testLossBeyondGraceMidClutchMoveOnlyDisengages() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 0.15, frames: 2)
        for i in 1...5 {
            harness.feed(indexRatio: 0.15, center: CGPoint(x: 0.5 + Double(i) * 0.01, y: 0.55))
        }

        let lostBatch = harness.feedLost(frames: 10)
        XCTAssertEqual(lostBatch, [.disengaged], "no drag was armed, so no dragEnded")
        XCTAssertEqual(harness.engine.state, .idle)
    }

    func testLossDuringPendingPinchNeverClicks() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 0.15, frames: 2)
        harness.feedLost(frames: 10)
        XCTAssertEqual(harness.intents.clickCount, 0, "a release never observed is not a tap")
    }

    // MARK: - External reset (pipeline teardown)

    func testResetMidDragReleasesTheButtonFirst() {
        var harness = EngineHarness()
        harness.feed(indexRatio: 1.0, frames: 3)
        harness.feed(indexRatio: 0.15, frames: 17)
        XCTAssertEqual(harness.engine.state, .dragging)

        // Stopping the pipeline mid-drag must obey the same safety invariant
        // as hand loss.
        XCTAssertEqual(harness.engine.reset(), [.dragEnded, .disengaged])
        XCTAssertEqual(harness.engine.state, .idle)
    }

    func testResetWhileIdleEmitsNothing() {
        var engine = GestureEngine()
        XCTAssertEqual(engine.reset(), [])
        XCTAssertEqual(engine.state, .idle)
    }

    // MARK: - Debug metrics

    func testExposesLastPinchMetrics() throws {
        var harness = EngineHarness()
        harness.feed(indexRatio: 0.5, middleRatio: 0.9)
        XCTAssertEqual(try XCTUnwrap(harness.engine.lastMetrics.index), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(harness.engine.lastMetrics.middle), 0.9, accuracy: 1e-9)
    }
}
