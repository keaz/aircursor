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

    func testScrollIsUnsupportedUntilM4() {
        let output = QuartzPointerOutput()
        let command = PointerCommand.scroll(dx: 0, dy: 10, phase: .began)
        XCTAssertThrowsError(try output.apply(command)) { error in
            XCTAssertEqual(error as? QuartzOutputError, .unsupportedCommand(command))
        }
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
