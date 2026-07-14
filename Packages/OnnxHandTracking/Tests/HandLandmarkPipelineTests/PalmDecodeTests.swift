import CoreGraphics
import Foundation
import HandLandmarkPipeline
import XCTest

final class PalmDecodeTests: XCTestCase {
    func testAnchorTableIsComplete() {
        XCTAssertEqual(PalmAnchors.count, 2016)
        XCTAssertEqual(PalmAnchors.flat.count, 2016 * 2)
    }

    func testSingleAnchorDecodeMatchesReferenceArithmetic() {
        // One anchor at (0.5, 0.5); zero deltas → box centred on the anchor.
        let scores: [Float] = [10] // sigmoid(10) ≈ 0.99995
        var regression = [Float](repeating: 0, count: 18)
        regression[2] = 96 // w delta → 96/192 = 0.5
        regression[3] = 48 // h delta → 48/192 = 0.25
        let anchors: [Float] = [0.5, 0.5]

        let cands = PalmDecode.candidates(
            scores: scores, regression: regression, anchors: anchors,
            modelInput: 192, scoreThreshold: 0.5
        )
        XCTAssertEqual(cands.count, 1)
        let c = cands[0]
        XCTAssertGreaterThan(c.score, 0.99)
        XCTAssertEqual(c.box.midX, 0.5, accuracy: 1e-6)
        XCTAssertEqual(c.box.midY, 0.5, accuracy: 1e-6)
        XCTAssertEqual(c.box.width, 0.5, accuracy: 1e-6)
        XCTAssertEqual(c.box.height, 0.25, accuracy: 1e-6)
        XCTAssertEqual(c.palmLandmarks.count, 7)
        XCTAssertEqual(c.palmLandmarks[0], CGPoint(x: 0.5, y: 0.5)) // zero delta → anchor
    }

    func testScoreThresholdFiltersWeakAnchors() {
        let scores: [Float] = [10, -10] // sigmoid: ~1.0, ~0.0
        let regression = [Float](repeating: 0, count: 36)
        let anchors: [Float] = [0.5, 0.5, 0.3, 0.3]
        let cands = PalmDecode.candidates(
            scores: scores, regression: regression, anchors: anchors,
            modelInput: 192, scoreThreshold: 0.5
        )
        XCTAssertEqual(cands.count, 1, "the weak anchor is dropped")
    }

    func testNonMaxSuppressionKeepsTheStrongestOfOverlappingBoxes() {
        let a = PalmCandidate(box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), palmLandmarks: [], score: 0.9)
        let b = PalmCandidate(box: CGRect(x: 0.41, y: 0.41, width: 0.2, height: 0.2), palmLandmarks: [], score: 0.7)
        let far = PalmCandidate(box: CGRect(x: 0.0, y: 0.0, width: 0.1, height: 0.1), palmLandmarks: [], score: 0.8)
        let kept = PalmDecode.nonMaxSuppressed([a, b, far], iouThreshold: 0.3)
        XCTAssertEqual(kept.count, 2, "the overlapping weaker box is suppressed; the far one survives")
        XCTAssertTrue(kept.contains(a))
        XCTAssertTrue(kept.contains(far))
        XCTAssertFalse(kept.contains(b))
    }

    func testBestReturnsHighestScorePalm() {
        let scores: [Float] = [2, 5, -1]
        let regression = [Float](repeating: 0, count: 54)
        let anchors: [Float] = [0.2, 0.2, 0.8, 0.8, 0.5, 0.5]
        let best = PalmDecode.best(
            scores: scores, regression: regression, anchors: anchors,
            modelInput: 192, scoreThreshold: 0.5, iouThreshold: 0.3
        )
        // anchor 1 (score sigmoid(5)≈0.993) is the strongest → box centred at (0.8,0.8).
        XCTAssertEqual(try XCTUnwrap(best).box.midX, 0.8, accuracy: 1e-6)
    }
}
