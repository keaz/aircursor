import CoreGraphics
import GestureEngine
import HandPoseCore
import XCTest

/// v2 transition coverage: pointing clutch, pinch-is-the-button with entry
/// gating, two-finger scroll and tap, zoom arming, grace, toggles, teardown.
final class GestureEngineTransitionTests: XCTestCase {
    // MARK: - Pointing clutch

    func testPointingEngagesMovesAndNeutralDisengages() {
        var harness = EngineHarness()
        harness.fist(frames: 2)
        harness.point(frames: 2) // calm pose debounces in over poseReleaseFrames
        XCTAssertEqual(harness.intents, [.engaged])

        let batch = harness.point(center: CGPoint(x: 0.52, y: 0.54))
        guard case .moveBy(let dx, let dy)? = batch.first, batch.count == 1 else {
            return XCTFail("expected one moveBy, got \(batch)")
        }
        XCTAssertEqual(dx, 0.02, accuracy: 1e-9)
        XCTAssertEqual(dy, -0.01, accuracy: 1e-9)

        harness.fist(frames: 2)
        XCTAssertEqual(harness.intents.last, .disengaged)
        XCTAssertEqual(harness.engine.state, .neutral)
    }

    func testOpenPalmFreezesTheCursor() {
        var harness = EngineHarness()
        harness.point(frames: 3)
        // Open palm takes a couple of frames to debounce in; once it does the
        // clutch disengages.
        harness.feed(fingers: .init(index: true, middle: true, ring: true, little: true), frames: 3)
        XCTAssertTrue(harness.intents.contains(.disengaged))
        XCTAssertEqual(harness.engine.state, .palm)

        let moved = harness.feed(
            fingers: .init(index: true, middle: true, ring: true, little: true),
            center: CGPoint(x: 0.53, y: 0.54) // below the swipe threshold
        )
        XCTAssertEqual(moved, [], "open palm must not move the cursor")
    }

    // MARK: - Pinch is the button (entry-gated)

    func testPinchFromPointPressesAndReleasesLeft() {
        var harness = EngineHarness()
        harness.point(frames: 2)
        XCTAssertEqual(harness.intents, [.engaged])
        // The pinch adopts over poseAdoptFrames before it presses.
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 3)
        XCTAssertEqual(harness.intents, [.engaged, .pressed(.left)])

        // Separate past the open threshold for poseReleaseFrames to end it.
        harness.feed(fingers: .init(index: true), indexPinch: 0.8, frames: 2)
        XCTAssertEqual(harness.intents, [.engaged, .pressed(.left), .released(.left)])
        XCTAssertEqual(harness.engine.state, .pointing, "release back to point keeps the clutch")
    }

    func testPinchDragMovesWhilePressed() throws {
        var harness = EngineHarness()
        harness.point(frames: 3) // arm + establish pointing
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 4) // press
        for i in 1...5 {
            harness.feed(
                fingers: .init(index: true),
                indexPinch: 0.2,
                center: CGPoint(x: 0.5 + Double(i) * 0.01, y: 0.55)
            )
        }
        // Enough calm frames to clear the release debounce (poseReleaseFrames).
        harness.fist(frames: 3)

        XCTAssertEqual(harness.intents.pressCount(.left), 1)
        XCTAssertGreaterThanOrEqual(harness.intents.moveCount, 5, "drag moves flow while pressed")
        // Guarded so a regression reports the emitted intents instead of a
        // fatal nil-unwrap that aborts the whole test process.
        let releaseIndex = try XCTUnwrap(
            harness.intents.firstIndex(of: .released(.left)),
            "expected a button-up; got \(harness.intents)"
        )
        let disengageIndex = try XCTUnwrap(
            harness.intents.firstIndex(of: .disengaged),
            "expected a disengage; got \(harness.intents)"
        )
        XCTAssertLessThan(releaseIndex, disengageIndex, "button up before clutch release")
    }

    func testPinchFromNeutralNeverPresses() {
        var harness = EngineHarness()
        harness.fist(frames: 3)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 3)
        XCTAssertEqual(harness.intents.pressCount(), 0, "neutral-formed pinches arm zoom, not the button")
    }

    // MARK: - Zoom (pinch armed from neutral)

    func testZoomSpreadStepsAndRearmsOnReclose() {
        var harness = EngineHarness()
        harness.fist(frames: 3)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 3) // adopt the pinch → arm zoom
        harness.feed(fingers: .init(), indexPinch: 1.2)            // spread past 1.15
        XCTAssertEqual(harness.intents.systemCount(.zoomStepIn), 1)

        harness.feed(fingers: .init(), indexPinch: 1.38)           // past 1.30
        XCTAssertEqual(harness.intents.systemCount(.zoomStepIn), 2)

        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 2) // re-close re-arms
        harness.feed(fingers: .init(), indexPinch: 1.2)
        XCTAssertEqual(harness.intents.systemCount(.zoomStepIn), 3)
        XCTAssertEqual(harness.intents.pressCount(), 0)
    }

    func testPointingNeverExitsZoom() {
        // Spreads read as Point with real wrist drift — the recordings prove
        // pose+motion can't separate them from pointing, so point never
        // leaves zoom, no matter how long or how far it moves.
        var harness = EngineHarness()
        harness.fist(frames: 3)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 3) // adopt the pinch → zoom
        XCTAssertEqual(harness.engine.state, .zooming)

        // 10 frames (~0.33s) is well under the zoom idle-timeout, so pointing
        // does not exit zoom here.
        for i in 1...10 {
            harness.point(center: CGPoint(x: 0.5 + Double(i) * 0.03, y: 0.55))
        }
        XCTAssertEqual(harness.engine.state, .zooming)
        XCTAssertEqual(harness.intents.count(of: .engaged), 0)
        XCTAssertEqual(harness.intents.pressCount(), 0)
    }

    func testSustainedOpenPalmExitsZoomAndClickingWorksAgain() {
        var harness = EngineHarness()
        harness.fist(frames: 3)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 3)
        XCTAssertEqual(harness.engine.state, .zooming)

        // Exiting zoom via palm clears both the pose debounce and the
        // zoom-exit streak, so feed a sustained palm.
        harness.feed(
            fingers: .init(index: true, middle: true, ring: true, little: true),
            frames: 5
        )
        XCTAssertEqual(harness.engine.state, .palm, "a sustained open palm releases zoom")

        harness.point(frames: 3)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 3)
        XCTAssertEqual(harness.intents.pressCount(.left), 1, "pinch-from-point presses again")
    }

    // MARK: - Scroll and two-finger tap

    func testScrollEmitsAfterDeadZoneAndEndsOnExit() throws {
        var harness = EngineHarness()
        harness.point(frames: 2)
        // Two-finger pose adopts over poseAdoptFrames, then moves upward each
        // frame well past the dead zone.
        for i in 0...9 {
            harness.feed(
                fingers: .init(index: true, middle: true),
                center: CGPoint(x: 0.5, y: 0.55 - Double(i) * 0.01)
            )
        }
        XCTAssertGreaterThanOrEqual(harness.intents.scrollCount, 3)
        let upScrolls = harness.intents.allSatisfy { intent in
            if case .scrollBy(_, let dy) = intent { return dy < 0 }
            return true
        }
        XCTAssertTrue(upScrolls)

        harness.point(frames: 2) // exit the scroll pose
        XCTAssertEqual(harness.intents.last, .engaged)
        XCTAssertEqual(harness.intents.count(of: .scrollEnded), 1)
        let endIndex = try XCTUnwrap(harness.intents.firstIndex(of: .scrollEnded))
        let engageIndex = try XCTUnwrap(harness.intents.lastIndex(of: .engaged))
        XCTAssertLessThan(endIndex, engageIndex, "scroll phase closes before re-engaging")
    }

    func testTwoFingerTapRightClicks() {
        var harness = EngineHarness()
        harness.point(frames: 3)
        harness.feed(fingers: .init(index: true, middle: true), frames: 4) // adopt scroll + brief still hold
        harness.point(frames: 2) // exit to point → the two-finger tap resolves

        XCTAssertEqual(harness.intents.pressCount(.right), 1)
        XCTAssertEqual(harness.intents.releaseCount(.right), 1)
        XCTAssertEqual(harness.intents.scrollCount, 0, "a tap never scrolls")
        XCTAssertEqual(harness.intents.count(of: .scrollEnded), 0)
    }

    func testSingleFrameScrollBlipDoesNothing() {
        var harness = EngineHarness()
        harness.point(frames: 3)
        harness.feed(fingers: .init(index: true, middle: true), frames: 1)
        harness.point(frames: 1)
        XCTAssertEqual(harness.intents.pressCount(.right), 0, "one-frame blips must not right-click")
        XCTAssertEqual(harness.intents.scrollCount, 0)
    }

    func testLongStillTwoFingerHoldIsNotATap() {
        var harness = EngineHarness()
        harness.point(frames: 3)
        harness.feed(fingers: .init(index: true, middle: true), frames: 12) // 400 ms still
        harness.point(frames: 1)
        XCTAssertEqual(harness.intents.pressCount(.right), 0, "held past tapDuration is not a tap")
    }

    // MARK: - Toggles

    func testDisabledLeftButtonKeepsMovementButNeverPresses() {
        var config = GestureConfig()
        config.leftButtonEnabled = false
        var harness = EngineHarness(config: config)
        harness.point(frames: 2)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 2)
        harness.feed(
            fingers: .init(index: true), indexPinch: 0.2, center: CGPoint(x: 0.53, y: 0.55)
        )
        XCTAssertEqual(harness.intents.pressCount(), 0)
        XCTAssertGreaterThan(harness.intents.moveCount, 0, "movement still works while pinched")
    }

    func testDisabledRightButtonSuppressesTap() {
        var config = GestureConfig()
        config.rightButtonEnabled = false
        var harness = EngineHarness(config: config)
        harness.point(frames: 3)
        harness.feed(fingers: .init(index: true, middle: true), frames: 3)
        harness.point(frames: 1)
        XCTAssertEqual(harness.intents.pressCount(.right), 0)
    }

    func testDisabledScrollMakesTwoFingerPoseInert() {
        var config = GestureConfig()
        config.scrollEnabled = false
        var harness = EngineHarness(config: config)
        harness.point(frames: 2)
        for i in 0...6 {
            harness.feed(
                fingers: .init(index: true, middle: true),
                center: CGPoint(x: 0.5, y: 0.55 - Double(i) * 0.01)
            )
        }
        XCTAssertEqual(harness.intents.scrollCount, 0)
        XCTAssertEqual(harness.intents.count(of: .scrollEnded), 0)
    }

    func testDisabledZoomIgnoresNeutralPinch() {
        var config = GestureConfig()
        config.zoomEnabled = false
        var harness = EngineHarness(config: config)
        harness.fist(frames: 3)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 2)
        harness.feed(fingers: .init(), indexPinch: 1.3)
        XCTAssertEqual(harness.intents.systemCount(), 0)
    }

    // MARK: - Loss, grace, teardown

    func testBriefDropoutInsideGraceKeepsThePress() {
        var harness = EngineHarness()
        harness.point(frames: 3)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 4) // establish the press
        XCTAssertEqual(harness.engine.state, .pressed(.left))
        harness.feedLost(frames: 2) // ~66 ms < 100 ms grace
        XCTAssertEqual(harness.intents.releaseCount(), 0)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2)
        XCTAssertEqual(harness.engine.state, .pressed(.left))
    }

    func testLossBeyondGraceReleasesButtonThenDisengages() {
        var harness = EngineHarness()
        harness.point(frames: 3)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 4) // establish the press
        let lost = harness.feedLost(frames: 6) // 200 ms > grace
        XCTAssertEqual(lost, [.released(.left), .disengaged])
        XCTAssertEqual(harness.engine.state, .idle)
    }

    func testLossMidScrollEndsThePhase() {
        var harness = EngineHarness()
        harness.point(frames: 2)
        for i in 0...5 {
            harness.feed(
                fingers: .init(index: true, middle: true),
                center: CGPoint(x: 0.5, y: 0.55 - Double(i) * 0.01)
            )
        }
        let lost = harness.feedLost(frames: 6)
        XCTAssertEqual(lost, [.scrollEnded])
    }

    func testResetMidPressReleasesFirst() {
        var harness = EngineHarness()
        harness.point(frames: 2)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 4) // establish the press
        XCTAssertEqual(harness.engine.state, .pressed(.left))
        XCTAssertEqual(harness.engine.reset(), [.released(.left), .disengaged])
        XCTAssertEqual(harness.engine.state, .idle)
    }
}
