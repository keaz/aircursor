import Foundation
import HandPoseCore
import XCTest

/// Every committed fixture must decode, carry the current version, and hold a
/// physically plausible landmark sequence.
final class FixtureValidationTests: XCTestCase {
    func testAllCommittedFixturesAreValid() throws {
        let directory = FixtureLocations.fixturesDirectory
        let urls = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(urls.isEmpty, "No fixtures found in \(directory.path)")

        for url in urls {
            let data = try Data(contentsOf: url)
            let fixture = try JSONDecoder().decode(HandPoseFixture.self, from: data)
            let name = url.lastPathComponent

            XCTAssertEqual(fixture.version, HandPoseFixture.currentVersion, name)
            XCTAssertFalse(fixture.frames.isEmpty, "\(name): no frames")

            var previousTimestamp = -Double.infinity
            for (index, frame) in fixture.frames.enumerated() {
                XCTAssertGreaterThan(
                    frame.timestamp, previousTimestamp,
                    "\(name): timestamps must be strictly increasing at frame \(index)"
                )
                previousTimestamp = frame.timestamp

                for (joint, point) in frame.joints {
                    XCTAssertTrue(
                        (0...1).contains(point.x) && (0...1).contains(point.y),
                        "\(name): \(joint) out of normalized bounds at frame \(index)"
                    )
                }
            }
        }
    }
}
