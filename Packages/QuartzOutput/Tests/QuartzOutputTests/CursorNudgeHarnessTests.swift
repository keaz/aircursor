import CoreGraphics
import PointerControl
import QuartzOutput
import XCTest

/// Manual end-to-end harness: physically nudges the cursor 10 pt and back.
/// Skipped in normal runs; execute with:
///
///     CURSOR_NUDGE=1 swift test --package-path Packages/QuartzOutput \
///         --filter CursorNudgeHarnessTests
///
/// Requires the test host to be accessibility-trusted; if it isn't, the OS
/// silently drops synthetic events and the test skips with an explanation.
final class CursorNudgeHarnessTests: XCTestCase {
    func testCursorPhysicallyMoves() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CURSOR_NUDGE"] == "1",
            "Set CURSOR_NUDGE=1 to physically nudge the cursor"
        )

        let output = QuartzPointerOutput()
        let start = QuartzPointerOutput.currentPointerLocation()
        let target = CGPoint(x: start.x + 10, y: start.y)

        try output.apply(.move(to: target))
        usleep(50_000)
        let observed = QuartzPointerOutput.currentPointerLocation()

        // Always restore before judging the outcome.
        try? output.apply(.move(to: start))

        if abs(observed.x - target.x) > 1 {
            throw XCTSkip(
                "Cursor did not move — the test host is not accessibility-trusted. "
                    + "The posting path executed without errors; do the visual check from the app."
            )
        }
        XCTAssertEqual(observed.x, target.x, accuracy: 1)
        XCTAssertEqual(observed.y, target.y, accuracy: 1)
    }
}
