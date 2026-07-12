import CoreGraphics
@testable import HandTrackingKit
import HandPoseCore
import Vision
import XCTest

final class VisionConversionTests: XCTestCase {
    func testFlipsBothAxes() {
        // Vision: bottom-left origin, unmirrored. Hand space: top-left origin,
        // mirrored so moving the hand right increases x.
        XCTAssertEqual(
            VisionConversion.handSpacePoint(fromVision: CGPoint(x: 0, y: 0)),
            CGPoint(x: 1, y: 1)
        )
        XCTAssertEqual(
            VisionConversion.handSpacePoint(fromVision: CGPoint(x: 1, y: 1)),
            CGPoint(x: 0, y: 0)
        )
        XCTAssertEqual(
            VisionConversion.handSpacePoint(fromVision: CGPoint(x: 0.25, y: 0.75)),
            CGPoint(x: 0.75, y: 0.25)
        )
    }

    func testConversionIsAnInvolution() {
        let point = CGPoint(x: 0.31, y: 0.62)
        let twice = VisionConversion.handSpacePoint(
            fromVision: VisionConversion.handSpacePoint(fromVision: point)
        )
        XCTAssertEqual(twice.x, point.x, accuracy: 1e-12)
        XCTAssertEqual(twice.y, point.y, accuracy: 1e-12)
    }

    func testAllVisionJointsMapToDistinctHandJoints() {
        let visionJoints: [VNHumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip,
        ]
        XCTAssertEqual(visionJoints.count, HandJoint.allCases.count)

        var mapped = Set<HandJoint>()
        for name in visionJoints {
            guard let joint = VisionConversion.handJoint(for: name) else {
                XCTFail("Unmapped Vision joint \(name.rawValue.rawValue)")
                continue
            }
            mapped.insert(joint)
        }
        XCTAssertEqual(mapped.count, HandJoint.allCases.count)
    }
}
