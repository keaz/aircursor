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

    // Event construction is tested through makeEvent, which updates the
    // held-button state and returns the event without posting anything.

    func testMovesUseTheCorrectEventTypeAroundADrag() throws {
        let output = QuartzPointerOutput()
        let point = CGPoint(x: 10, y: 10)

        XCTAssertEqual(try output.makeEvent(for: .move(to: point)).type, .mouseMoved)

        XCTAssertEqual(
            try output.makeEvent(for: .buttonDown(.left, at: point)).type,
            .leftMouseDown
        )
        XCTAssertEqual(
            try output.makeEvent(for: .move(to: point)).type,
            .leftMouseDragged,
            "moves while the left button is held must be drag events"
        )
        XCTAssertEqual(
            try output.makeEvent(for: .buttonUp(.left, at: point)).type,
            .leftMouseUp
        )
        XCTAssertEqual(
            try output.makeEvent(for: .move(to: point)).type,
            .mouseMoved,
            "after button-up, moves are plain moves again"
        )
    }

    func testRightButtonEventTypes() throws {
        let output = QuartzPointerOutput()
        let point = CGPoint(x: 5, y: 5)

        XCTAssertEqual(
            try output.makeEvent(for: .buttonDown(.right, at: point)).type,
            .rightMouseDown
        )
        XCTAssertEqual(
            try output.makeEvent(for: .move(to: point)).type,
            .rightMouseDragged
        )
        XCTAssertEqual(
            try output.makeEvent(for: .buttonUp(.right, at: point)).type,
            .rightMouseUp
        )
    }

    func testButtonEventsCarryClickStateAndLocation() throws {
        let output = QuartzPointerOutput()
        let point = CGPoint(x: 123, y: 456)

        let down = try output.makeEvent(for: .buttonDown(.left, at: point))
        XCTAssertEqual(down.getIntegerValueField(.mouseEventClickState), 1)
        XCTAssertEqual(down.location, point)

        let up = try output.makeEvent(for: .buttonUp(.left, at: point))
        XCTAssertEqual(up.getIntegerValueField(.mouseEventClickState), 1)
        XCTAssertEqual(up.location, point)
    }

    func testScrollEventsCarryPixelDeltasAndPhases() throws {
        let output = QuartzPointerOutput()

        let began = try output.makeEvent(for: .scroll(dx: 4, dy: -12, phase: .began))
        XCTAssertEqual(began.type, .scrollWheel)
        XCTAssertEqual(began.getIntegerValueField(.scrollWheelEventIsContinuous), 1, "pixel scrolls are continuous")
        XCTAssertEqual(began.getIntegerValueField(.scrollWheelEventScrollPhase), 1) // kCGScrollPhaseBegan
        XCTAssertEqual(began.getIntegerValueField(.scrollWheelEventMomentumPhase), 0)
        XCTAssertEqual(began.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -12, "vertical keeps hand-space sign")
        XCTAssertEqual(began.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 4)

        let changed = try output.makeEvent(for: .scroll(dx: 0, dy: 6, phase: .changed))
        XCTAssertEqual(changed.getIntegerValueField(.scrollWheelEventScrollPhase), 2) // kCGScrollPhaseChanged

        let ended = try output.makeEvent(for: .scroll(dx: 0, dy: 0, phase: .ended))
        XCTAssertEqual(ended.getIntegerValueField(.scrollWheelEventScrollPhase), 4) // kCGScrollPhaseEnded
        XCTAssertEqual(ended.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 0)
    }

    func testScrollDeltasRoundToWholePixels() throws {
        let output = QuartzPointerOutput()
        let event = try output.makeEvent(for: .scroll(dx: 0, dy: 7.6, phase: .changed))
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 8)
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
