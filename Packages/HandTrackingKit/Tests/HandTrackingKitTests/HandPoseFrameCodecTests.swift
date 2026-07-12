import Foundation
import HandPoseCore
import XCTest

final class HandPoseFrameCodecTests: XCTestCase {
    func testFrameRoundTripsThroughFixtureJSON() throws {
        let frame = HandPoseFrame(
            joints: [
                .wrist: CGPoint(x: 0.5, y: 0.8),
                .thumbTip: CGPoint(x: 0.42, y: 0.55),
                .indexTip: CGPoint(x: 0.44, y: 0.52),
            ],
            timestamp: 0.016
        )
        let fixture = HandPoseFixture(frames: [frame])

        let data = try JSONEncoder().encode(fixture)
        let decoded = try JSONDecoder().decode(HandPoseFixture.self, from: data)

        XCTAssertEqual(decoded, fixture)
        XCTAssertEqual(decoded.version, HandPoseFixture.currentVersion)
    }

    func testUnknownJointNameFailsDecoding() {
        let json = Data(#"{"version":1,"frames":[{"timestamp":0,"joints":{"pinkyTip":[0.1,0.2]}}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(HandPoseFixture.self, from: json))
    }
}
