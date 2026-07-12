import CoreGraphics
import PointerControl
import QuartzOutput
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

    func testButtonAndScrollCommandsAreUnsupportedInM2() {
        let output = QuartzPointerOutput()
        let unsupported: [PointerCommand] = [
            .buttonDown(.left, at: .zero),
            .buttonUp(.left, at: .zero),
            .scroll(dx: 0, dy: 10, phase: .began),
        ]
        for command in unsupported {
            XCTAssertThrowsError(try output.apply(command)) { error in
                XCTAssertEqual(error as? QuartzOutputError, .unsupportedCommand(command))
            }
        }
    }

    func testCurrentPointerLocationIsFinite() {
        let location = QuartzPointerOutput.currentPointerLocation()
        XCTAssertTrue(location.x.isFinite)
        XCTAssertTrue(location.y.isFinite)
    }

    func testActiveDisplayBoundsReportsAtLeastOneDisplay() {
        let bounds = QuartzDisplays.activeDisplayBounds()
        XCTAssertFalse(bounds.isEmpty)
        for rect in bounds {
            XCTAssertGreaterThan(rect.width, 0)
            XCTAssertGreaterThan(rect.height, 0)
        }
    }

    func testPermissionCheckDoesNotCrash() {
        _ = QuartzPointerOutput.hasAccessibilityPermission
    }
}
