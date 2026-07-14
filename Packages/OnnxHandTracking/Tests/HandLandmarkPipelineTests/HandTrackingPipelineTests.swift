import CoreGraphics
import HandLandmarkPipeline
import HandPoseCore
import XCTest

/// A scripted model whose per-frame results the test controls, and which
/// records how it was called so track continuity can be asserted.
private final class ScriptedModel: HandDetectionModel {
    typealias Image = Int // frame index

    var palm: [Int: PalmDetection] = [:]
    var landmarks: [Int: HandLandmarks] = [:]
    var throwOnPalm = false

    private(set) var palmCalls: [Int] = []
    private(set) var landmarkCalls: [(frame: Int, crop: CGRect)] = []

    struct Boom: Error {}

    func detectPalm(in image: Int) throws -> PalmDetection? {
        palmCalls.append(image)
        if throwOnPalm { throw Boom() }
        return palm[image]
    }

    func locateLandmarks(in image: Int, crop: CGRect) throws -> HandLandmarks? {
        landmarkCalls.append((image, crop))
        return landmarks[image]
    }
}

final class HandTrackingPipelineTests: XCTestCase {
    private func full(_ presence: Double = 0.9) -> HandLandmarks {
        HandLandmarks(points: (0..<21).map { CGPoint(x: Double($0) / 21, y: 0.5) }, presence: presence)
    }
    private let palmHit = PalmDetection(box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), score: 0.9)

    func testNoPalmYieldsEmptyFrameAndNoTrack() {
        let model = ScriptedModel()
        var pipeline = HandTrackingPipeline(model: model)
        let frame = pipeline.process(0, timestamp: 0)
        XCTAssertTrue(frame.joints.isEmpty)
        XCTAssertFalse(pipeline.isTracking)
    }

    func testWeakPalmScoreIsRejected() {
        let model = ScriptedModel()
        model.palm[0] = PalmDetection(box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), score: 0.3)
        model.landmarks[0] = full()
        var pipeline = HandTrackingPipeline(model: model, config: .init(palmScoreThreshold: 0.5))
        XCTAssertTrue(pipeline.process(0, timestamp: 0).joints.isEmpty, "phantom gate rejects a weak palm")
        XCTAssertTrue(model.landmarkCalls.isEmpty, "landmark model not run without a palm")
    }

    func testPalmThenLandmarkProducesA21JointFrame() {
        let model = ScriptedModel()
        model.palm[0] = palmHit
        model.landmarks[0] = full()
        var pipeline = HandTrackingPipeline(model: model)
        let frame = pipeline.process(0, timestamp: 5)
        XCTAssertEqual(frame.joints.count, 21)
        XCTAssertEqual(frame.timestamp, 5)
        XCTAssertTrue(pipeline.isTracking)
    }

    func testTrackingSkipsPalmDetectorWhileHeld() {
        let model = ScriptedModel()
        model.palm[0] = palmHit
        model.landmarks[0] = full(); model.landmarks[1] = full(); model.landmarks[2] = full()
        var pipeline = HandTrackingPipeline(model: model)
        _ = pipeline.process(0, timestamp: 0)
        _ = pipeline.process(1, timestamp: 1)
        _ = pipeline.process(2, timestamp: 2)
        XCTAssertEqual(model.palmCalls, [0], "palm detector runs once, then the track follows")
        XCTAssertEqual(model.landmarkCalls.count, 3)
    }

    func testLandmarkLossDropsTrackAndRedetects() {
        let model = ScriptedModel()
        model.palm[0] = palmHit; model.palm[2] = palmHit
        model.landmarks[0] = full() // frame 1 has no landmark result → loss
        model.landmarks[2] = full()
        var pipeline = HandTrackingPipeline(model: model)
        _ = pipeline.process(0, timestamp: 0)
        let lost = pipeline.process(1, timestamp: 1)
        XCTAssertTrue(lost.joints.isEmpty)
        XCTAssertFalse(pipeline.isTracking)
        _ = pipeline.process(2, timestamp: 2)
        XCTAssertEqual(model.palmCalls, [0, 2], "the palm detector re-runs after a loss")
    }

    func testLowLandmarkPresenceDropsTrack() {
        let model = ScriptedModel()
        model.palm[0] = palmHit
        model.landmarks[0] = full(0.2) // below threshold
        var pipeline = HandTrackingPipeline(model: model, config: .init(landmarkPresenceThreshold: 0.5))
        XCTAssertTrue(pipeline.process(0, timestamp: 0).joints.isEmpty)
        XCTAssertFalse(pipeline.isTracking)
    }

    func testWristMapsThroughCropInverseAndMirror() {
        let model = ScriptedModel()
        // Full-frame crop (scale 1, box fills frame) so only the mirror applies.
        model.palm[0] = PalmDetection(box: CGRect(x: 0, y: 0, width: 1, height: 1), score: 0.9)
        var pts = Array(repeating: CGPoint(x: 0.5, y: 0.5), count: 21)
        pts[0] = CGPoint(x: 0.3, y: 0.7) // wrist in crop space
        model.landmarks[0] = HandLandmarks(points: pts, presence: 0.9)
        var pipeline = HandTrackingPipeline(model: model, config: .init(palmCropScale: 1.0))
        let frame = pipeline.process(0, timestamp: 0)
        // crop = full frame → image (0.3,0.7); mirror x → (0.7, 0.7).
        XCTAssertEqual(frame.joints[.wrist]!.x, 0.7, accuracy: 1e-9)
        XCTAssertEqual(frame.joints[.wrist]!.y, 0.7, accuracy: 1e-9)
    }

    func testInferenceErrorIsTreatedAsLoss() {
        let model = ScriptedModel()
        model.throwOnPalm = true
        var pipeline = HandTrackingPipeline(model: model)
        let frame = pipeline.process(0, timestamp: 0)
        XCTAssertTrue(frame.joints.isEmpty)
        XCTAssertNotNil(pipeline.lastError, "the error is surfaced, not swallowed silently")
        XCTAssertFalse(pipeline.isTracking)
    }

    func testResetForcesReacquisition() {
        let model = ScriptedModel()
        model.palm[0] = palmHit; model.palm[1] = palmHit
        model.landmarks[0] = full(); model.landmarks[1] = full()
        var pipeline = HandTrackingPipeline(model: model)
        _ = pipeline.process(0, timestamp: 0)
        pipeline.reset()
        XCTAssertFalse(pipeline.isTracking)
        _ = pipeline.process(1, timestamp: 1)
        XCTAssertEqual(model.palmCalls, [0, 1], "reset makes the next frame re-detect")
    }
}
