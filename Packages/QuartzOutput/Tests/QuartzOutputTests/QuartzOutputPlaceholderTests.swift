import PointerControl
import QuartzOutput
import XCTest

final class QuartzOutputPlaceholderTests: XCTestCase {
    // M2 replaces this with tests around event construction (no posting in CI).
    func testPermissionCheckDoesNotCrash() {
        _ = QuartzPointerOutput.hasAccessibilityPermission
    }

    func testApplyIsNotImplementedYet() {
        let output = QuartzPointerOutput()
        XCTAssertThrowsError(try output.apply(.move(to: .zero))) { error in
            XCTAssertEqual(error as? QuartzOutputError, .notImplemented)
        }
    }
}
