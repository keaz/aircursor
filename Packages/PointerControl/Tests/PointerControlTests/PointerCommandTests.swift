import GestureEngine
import PointerControl
import XCTest

final class PointerCommandTests: XCTestCase {
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
