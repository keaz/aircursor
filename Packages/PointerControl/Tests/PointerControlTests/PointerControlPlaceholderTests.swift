import GestureEngine
import PointerControl
import XCTest

final class PointerControlPlaceholderTests: XCTestCase {
    // M2 replaces this with tests for the clutch anchor, gain curve, and
    // display-bounds clamping.
    func testCommandEquality() {
        XCTAssertEqual(
            PointerCommand.move(to: CGPoint(x: 10, y: 20)),
            PointerCommand.move(to: CGPoint(x: 10, y: 20))
        )
        XCTAssertNotEqual(
            PointerCommand.buttonDown(.left, at: .zero),
            PointerCommand.buttonUp(.left, at: .zero)
        )
    }
}
