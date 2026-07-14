import Foundation
@testable import OnnxHandTracking
import XCTest

/// Verifies the ONNX stack works end to end in this environment: the bundled
/// models load through ONNX Runtime, expose their real tensor names, and run
/// a forward pass. The exact I/O names are printed so the decode code can be
/// written against them (not guessed).
final class OrtModelTests: XCTestCase {
    func testBothModelsLoadAndExposeTheirIO() throws {
        let palmURL = try XCTUnwrap(BundledModels.palmDetectorURL, "palm model missing from bundle")
        let palm = try OrtModel(modelPath: palmURL.path)
        print("PALM inputs=\(palm.inputNames) outputs=\(palm.outputNames)")
        XCTAssertFalse(palm.inputNames.isEmpty)
        XCTAssertFalse(palm.outputNames.isEmpty)

        let handURL = try XCTUnwrap(BundledModels.handLandmarkerURL, "hand model missing from bundle")
        let hand = try OrtModel(modelPath: handURL.path)
        print("HAND inputs=\(hand.inputNames) outputs=\(hand.outputNames)")
        XCTAssertFalse(hand.inputNames.isEmpty)
        XCTAssertFalse(hand.outputNames.isEmpty)
    }

    func testPalmForwardPassProducesOutputs() throws {
        let url = try XCTUnwrap(BundledModels.palmDetectorURL)
        let model = try OrtModel(modelPath: url.path)
        // NHWC [1,192,192,3] of zeros — just proves inference runs and the
        // output sizes match expectations.
        let outputs = try model.run(input: [Float](repeating: 0, count: 192 * 192 * 3), shape: [1, 192, 192, 3])
        // Contract discovered from the model: 2016 anchors × 18 regression
        // (4 box + 7×2 landmark deltas) and 2016 per-anchor scores.
        XCTAssertEqual(outputs["Identity"]?.count, 2016 * 18)
        XCTAssertEqual(outputs["Identity_1"]?.count, 2016)
    }

    func testHandForwardPassProducesOutputs() throws {
        let url = try XCTUnwrap(BundledModels.handLandmarkerURL)
        let model = try OrtModel(modelPath: url.path)
        let outputs = try model.run(input: [Float](repeating: 0, count: 224 * 224 * 3), shape: [1, 224, 224, 3])
        // Contract: screen landmarks (21×3), presence (1), handedness (1),
        // world landmarks (21×3).
        XCTAssertEqual(outputs["Identity"]?.count, 63)
        XCTAssertEqual(outputs["Identity_1"]?.count, 1)
        XCTAssertEqual(outputs["Identity_2"]?.count, 1)
        XCTAssertEqual(outputs["Identity_3"]?.count, 63)
    }
}
