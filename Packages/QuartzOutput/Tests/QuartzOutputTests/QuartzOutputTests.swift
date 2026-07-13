import CoreGraphics
import GestureEngine
import PointerControl
@testable import QuartzOutput
import XCTest

final class QuartzOutputTests: XCTestCase {
    // Posting is exercised by moving to the cursor's *current* location — a
    // visual no-op that still walks the full event-creation path. (Without
    // accessibility trust the system quietly drops the event; the API
    // surface behaves identically.)
    func testMoveToCurrentLocationDoesNotThrow() {
        let output = QuartzPointerOutput()
        let here = QuartzPointerOutput.currentPointerLocation()
        XCTAssertNoThrow(try output.apply(.move(to: here)))
    }

    // Event construction is tested through makeEvents, which updates the
    // held-button/click state and returns events without posting anything.

    private func onlyEvent(_ events: [CGEvent], file: StaticString = #filePath, line: UInt = #line) throws -> CGEvent {
        XCTAssertEqual(events.count, 1, file: file, line: line)
        return try XCTUnwrap(events.first, file: file, line: line)
    }

    func testMovesUseTheCorrectEventTypeAroundADrag() throws {
        let output = QuartzPointerOutput()
        let point = CGPoint(x: 10, y: 10)

        XCTAssertEqual(try onlyEvent(output.makeEvents(for: .move(to: point))).type, .mouseMoved)

        XCTAssertEqual(
            try onlyEvent(output.makeEvents(for: .buttonDown(.left, at: point))).type,
            .leftMouseDown
        )
        XCTAssertEqual(
            try onlyEvent(output.makeEvents(for: .move(to: point))).type,
            .leftMouseDragged,
            "moves while the left button is held must be drag events"
        )
        XCTAssertEqual(
            try onlyEvent(output.makeEvents(for: .buttonUp(.left, at: point))).type,
            .leftMouseUp
        )
        XCTAssertEqual(
            try onlyEvent(output.makeEvents(for: .move(to: point))).type,
            .mouseMoved,
            "after button-up, moves are plain moves again"
        )
    }

    func testRightButtonEventTypes() throws {
        let output = QuartzPointerOutput()
        let point = CGPoint(x: 5, y: 5)

        XCTAssertEqual(
            try onlyEvent(output.makeEvents(for: .buttonDown(.right, at: point))).type,
            .rightMouseDown
        )
        XCTAssertEqual(
            try onlyEvent(output.makeEvents(for: .move(to: point))).type,
            .rightMouseDragged
        )
        XCTAssertEqual(
            try onlyEvent(output.makeEvents(for: .buttonUp(.right, at: point))).type,
            .rightMouseUp
        )
    }

    func testScrollEventsCarryPixelDeltasAndPhases() throws {
        let output = QuartzPointerOutput()

        let began = try onlyEvent(output.makeEvents(for: .scroll(dx: 4, dy: -12, phase: .began)))
        XCTAssertEqual(began.type, .scrollWheel)
        XCTAssertEqual(began.getIntegerValueField(.scrollWheelEventIsContinuous), 1, "pixel scrolls are continuous")
        XCTAssertEqual(began.getIntegerValueField(.scrollWheelEventScrollPhase), 1) // kCGScrollPhaseBegan
        XCTAssertEqual(began.getIntegerValueField(.scrollWheelEventMomentumPhase), 0)
        XCTAssertEqual(began.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -12, "vertical keeps hand-space sign")
        XCTAssertEqual(began.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 4)

        let changed = try onlyEvent(output.makeEvents(for: .scroll(dx: 0, dy: 6, phase: .changed)))
        XCTAssertEqual(changed.getIntegerValueField(.scrollWheelEventScrollPhase), 2) // kCGScrollPhaseChanged

        let ended = try onlyEvent(output.makeEvents(for: .scroll(dx: 0, dy: 0, phase: .ended)))
        XCTAssertEqual(ended.getIntegerValueField(.scrollWheelEventScrollPhase), 4) // kCGScrollPhaseEnded
        XCTAssertEqual(ended.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 0)
    }

    func testScrollDeltasRoundToWholePixels() throws {
        let output = QuartzPointerOutput()
        let event = try onlyEvent(output.makeEvents(for: .scroll(dx: 0, dy: 7.6, phase: .changed)))
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 8)
    }

    // MARK: - System actions → key chords

    func testSystemActionsPostKeyChords() throws {
        let output = QuartzPointerOutput()
        let cases: [(SystemAction, Int64, CGEventFlags)] = [
            (.spaceLeft, 123, .maskControl),      // ctrl+←
            (.spaceRight, 124, .maskControl),     // ctrl+→
            (.missionControl, 126, .maskControl), // ctrl+↑
            (.zoomStepIn, 24, .maskCommand),      // ⌘+
        ]
        for (action, keycode, flags) in cases {
            let events = try output.makeEvents(for: .system(action))
            XCTAssertEqual(events.count, 2, "\(action): key down + key up")
            XCTAssertEqual(events[0].type, .keyDown, "\(action)")
            XCTAssertEqual(events[1].type, .keyUp, "\(action)")
            for event in events {
                XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), keycode, "\(action)")
                XCTAssertTrue(event.flags.contains(flags), "\(action) must carry its modifier")
            }
        }
    }

    // MARK: - Click coalescing (double/triple click)

    func testRapidSameSpotPressesEscalateClickState() throws {
        var now = 100.0
        let output = QuartzPointerOutput(now: { now })
        let point = CGPoint(x: 50, y: 50)

        let first = try onlyEvent(output.makeEvents(for: .buttonDown(.left, at: point)))
        XCTAssertEqual(first.getIntegerValueField(.mouseEventClickState), 1)
        let firstUp = try onlyEvent(output.makeEvents(for: .buttonUp(.left, at: point)))
        XCTAssertEqual(firstUp.getIntegerValueField(.mouseEventClickState), 1)

        now += 0.2
        let second = try onlyEvent(output.makeEvents(for: .buttonDown(.left, at: point)))
        XCTAssertEqual(second.getIntegerValueField(.mouseEventClickState), 2, "a quick re-press double-clicks")
        let secondUp = try onlyEvent(output.makeEvents(for: .buttonUp(.left, at: point)))
        XCTAssertEqual(secondUp.getIntegerValueField(.mouseEventClickState), 2)

        now += 0.2
        let third = try onlyEvent(output.makeEvents(for: .buttonDown(.left, at: point)))
        XCTAssertEqual(third.getIntegerValueField(.mouseEventClickState), 3)
    }

    func testSlowOrDistantPressesResetClickState() throws {
        var now = 100.0
        let output = QuartzPointerOutput(now: { now })
        let point = CGPoint(x: 50, y: 50)

        _ = try output.makeEvents(for: .buttonDown(.left, at: point))
        _ = try output.makeEvents(for: .buttonUp(.left, at: point))

        now += 1.0 // too slow
        let slow = try onlyEvent(output.makeEvents(for: .buttonDown(.left, at: point)))
        XCTAssertEqual(slow.getIntegerValueField(.mouseEventClickState), 1)
        _ = try output.makeEvents(for: .buttonUp(.left, at: point))

        now += 0.2 // fast but far away
        let far = try onlyEvent(output.makeEvents(for: .buttonDown(.left, at: CGPoint(x: 200, y: 200))))
        XCTAssertEqual(far.getIntegerValueField(.mouseEventClickState), 1)
    }

    func testDifferentButtonsDoNotCoalesce() throws {
        var now = 100.0
        let output = QuartzPointerOutput(now: { now })
        let point = CGPoint(x: 50, y: 50)

        _ = try output.makeEvents(for: .buttonDown(.left, at: point))
        _ = try output.makeEvents(for: .buttonUp(.left, at: point))
        now += 0.2
        let right = try onlyEvent(output.makeEvents(for: .buttonDown(.right, at: point)))
        XCTAssertEqual(right.getIntegerValueField(.mouseEventClickState), 1)
    }

    func testCurrentPointerLocationIsFinite() {
        let location = QuartzPointerOutput.currentPointerLocation()
        XCTAssertTrue(location.x.isFinite)
        XCTAssertTrue(location.y.isFinite)
    }

    func testActiveDisplayBoundsAreWellFormed() throws {
        let bounds = QuartzDisplays.activeDisplayBounds()
        // A locked or sleeping machine can legitimately report no active
        // displays; only the shape of reported rects is asserted.
        try XCTSkipIf(bounds.isEmpty, "no active displays (asleep/headless?)")
        for rect in bounds {
            XCTAssertGreaterThan(rect.width, 0)
            XCTAssertGreaterThan(rect.height, 0)
        }
    }

    func testPermissionCheckDoesNotCrash() {
        _ = QuartzPointerOutput.hasAccessibilityPermission
    }
}
