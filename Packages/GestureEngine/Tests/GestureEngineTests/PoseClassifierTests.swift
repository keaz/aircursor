import CoreGraphics
import GestureEngine
import HandPoseCore
import XCTest

final class PoseClassifierTests: XCTestCase {
    private var classifier = PoseClassifier()
    private var timestamp: TimeInterval = 0

    private func classify(
        fingers: TestHandV2.Fingers,
        indexPinch: Double? = nil,
        center: CGPoint = CGPoint(x: 0.5, y: 0.55)
    ) -> PoseSnapshot? {
        defer { timestamp += 1.0 / 30 }
        return classifier.classify(HandPoseFrame(
            joints: TestHandV2.joints(center: center, fingers: fingers, indexPinch: indexPinch),
            timestamp: timestamp
        ))
    }

    // MARK: - Pose vocabulary

    func testPointPose() throws {
        let snapshot = try XCTUnwrap(classify(fingers: .init(index: true)))
        XCTAssertEqual(snapshot.pose, .point)
        XCTAssertEqual(snapshot.fingers, FingerStates(index: true, middle: false, ring: false, little: false))
    }

    func testScrollPose() throws {
        let snapshot = try XCTUnwrap(classify(fingers: .init(index: true, middle: true)))
        XCTAssertEqual(snapshot.pose, .scroll)
    }

    func testOpenPalmPose() throws {
        let snapshot = try XCTUnwrap(
            classify(fingers: .init(index: true, middle: true, ring: true, little: true))
        )
        XCTAssertEqual(snapshot.pose, .openPalm)
        XCTAssertEqual(snapshot.fingers.extendedCount, 4)
    }

    func testFistIsNeutral() throws {
        let snapshot = try XCTUnwrap(classify(fingers: .init()))
        XCTAssertEqual(snapshot.pose, .neutral)
        XCTAssertEqual(snapshot.fingers.extendedCount, 0)
    }

    func testThreeFingersIsNeutralNotScrollOrPalm() throws {
        let snapshot = try XCTUnwrap(
            classify(fingers: .init(index: true, middle: true, ring: true))
        )
        XCTAssertEqual(snapshot.pose, .neutral, "undefined finger combinations stay neutral")
    }

    func testPinchBeatsEveryExtensionPose() throws {
        let snapshot = try XCTUnwrap(
            classify(fingers: .init(index: true, middle: true, ring: true, little: true), indexPinch: 0.2)
        )
        XCTAssertEqual(snapshot.pose, .pinched)
        XCTAssertEqual(snapshot.indexPinchMetric, 0.2, accuracy: 1e-9)
    }

    // MARK: - Hysteresis

    func testPinchHysteresisHoldsInsideBand() throws {
        _ = classify(fingers: .init(index: true), indexPinch: 0.2)
        let inBand = try XCTUnwrap(classify(fingers: .init(index: true), indexPinch: 0.45))
        XCTAssertEqual(inBand.pose, .pinched, "0.45 is inside the 0.35/0.55 band")
        let released = try XCTUnwrap(classify(fingers: .init(index: true), indexPinch: 0.6))
        XCTAssertEqual(released.pose, .point)
    }

    func testExtensionHysteresisPreventsPoseFlicker() throws {
        _ = classify(fingers: .init(index: true))
        // Index extension wobbling inside the 0.95–1.15 band must not drop
        // the Point pose.
        for ratio in [1.05, 0.97, 1.12, 1.0, 1.14] {
            let snapshot = try XCTUnwrap(classify(
                fingers: .init(index: ratio, middle: 0.55, ring: 0.55, little: 0.55)
            ))
            XCTAssertEqual(snapshot.pose, .point, "ratio \(ratio) flickered the pose")
        }
        let dropped = try XCTUnwrap(classify(
            fingers: .init(index: 0.9, middle: 0.55, ring: 0.55, little: 0.55)
        ))
        XCTAssertEqual(dropped.pose, .neutral)
    }

    // MARK: - Degraded input

    func testMissingFingerJointHoldsItsPreviousState() throws {
        _ = classify(fingers: .init(index: true))
        var joints = TestHandV2.joints(fingers: .init(index: true))
        joints[.littleTip] = nil
        joints[.littlePIP] = nil
        let snapshot = try XCTUnwrap(
            classifier.classify(HandPoseFrame(joints: joints, timestamp: timestamp))
        )
        XCTAssertEqual(snapshot.pose, .point, "a dropped little finger must not break the pose")
    }

    func testMissingCoreJointsReturnNil() {
        var joints = TestHandV2.joints(fingers: .init(index: true))
        joints[.thumbTip] = nil
        XCTAssertNil(classifier.classify(HandPoseFrame(joints: joints, timestamp: 0)))
        XCTAssertNil(classifier.classify(HandPoseFrame(joints: [:], timestamp: 1)))
    }

    func testResetForgetsGateState() throws {
        _ = classify(fingers: .init(index: true), indexPinch: 0.2)
        classifier.reset()
        // Inside the pinch band after reset: the gate must be open again.
        let snapshot = try XCTUnwrap(classify(fingers: .init(index: true), indexPinch: 0.45))
        XCTAssertEqual(snapshot.pose, .point)
    }
}
