import CoreGraphics
import HandLandmarkPipeline
import HandPoseCore
import XCTest

final class MediaPipeLandmarksTests: XCTestCase {
    func testJointOrderIs21DistinctJoints() {
        XCTAssertEqual(MediaPipeLandmarks.jointOrder.count, 21)
        XCTAssertEqual(Set(MediaPipeLandmarks.jointOrder).count, 21, "no joint mapped twice")
        XCTAssertEqual(MediaPipeLandmarks.jointOrder.first, .wrist, "index 0 is the wrist")
        XCTAssertEqual(MediaPipeLandmarks.jointOrder[4], .thumbTip)
        XCTAssertEqual(MediaPipeLandmarks.jointOrder[8], .indexTip)
        XCTAssertEqual(MediaPipeLandmarks.jointOrder[20], .littleTip, "index 20 is the pinky tip")
    }

    func testHandSpaceMirrorsXOnly() {
        // MediaPipe is top-left origin, so only x flips (unlike Vision).
        XCTAssertEqual(
            MediaPipeLandmarks.handSpacePoint(fromImageNormalized: CGPoint(x: 0.25, y: 0.75)),
            CGPoint(x: 0.75, y: 0.75)
        )
    }

    func testFrameMapsAll21LandmarksIntoHandSpace() {
        let points = (0..<21).map { CGPoint(x: Double($0) / 21, y: 0.5) }
        let frame = MediaPipeLandmarks.frame(
            from: HandLandmarks(points: points, presence: 0.9),
            timestamp: 1.0,
            minimumPresence: 0.5
        )
        XCTAssertEqual(frame.joints.count, 21)
        XCTAssertEqual(frame.timestamp, 1.0)
        // Wrist (index 0, x=0) mirrors to x=1.
        XCTAssertEqual(frame.joints[.wrist], CGPoint(x: 1, y: 0.5))
    }

    func testLowPresenceYieldsEmptyFrame() {
        let points = Array(repeating: CGPoint(x: 0.5, y: 0.5), count: 21)
        let frame = MediaPipeLandmarks.frame(
            from: HandLandmarks(points: points, presence: 0.3),
            timestamp: 0,
            minimumPresence: 0.5
        )
        XCTAssertTrue(frame.joints.isEmpty, "below the presence gate is treated as no hand")
    }

    func testWrongLandmarkCountYieldsEmptyFrame() {
        let frame = MediaPipeLandmarks.frame(
            from: HandLandmarks(points: [CGPoint(x: 0.5, y: 0.5)], presence: 0.9),
            timestamp: 0,
            minimumPresence: 0.5
        )
        XCTAssertTrue(frame.joints.isEmpty)
    }
}
