import Foundation
import HandPoseCore
import XCTest

/// Every committed fixture must decode, carry the current version, and hold
/// a plausible landmark sequence. The fixture set is the user's real
/// recorded gestures in `Fixtures/recorded/` (extracted from video by
/// `fixture-extract` — landmarks only).
final class FixtureValidationTests: XCTestCase {
    /// `<repo>/Fixtures`, resolved relative to this source file.
    private static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // HandTrackingKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // HandTrackingKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    func testAllCommittedFixturesAreValid() throws {
        let root = Self.fixturesDirectory
        let urls = try FileManager.default
            .contentsOfDirectory(at: root.appendingPathComponent("recorded"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertGreaterThanOrEqual(urls.count, 7, "the recorded gesture set is incomplete")

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
                    // Vision occasionally reports joints slightly outside
                    // the frame; allow a small margin.
                    XCTAssertTrue(
                        (-0.1...1.1).contains(point.x) && (-0.1...1.1).contains(point.y),
                        "\(name): \(joint) implausibly out of bounds at frame \(index)"
                    )
                }
            }
        }
    }
}
