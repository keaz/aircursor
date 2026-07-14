import CoreGraphics
import HandLandmarkPipeline
import XCTest

final class LetterboxAndDecodeTests: XCTestCase {
    // A 640×480 image into 192: ratio = 192/640 = 0.3, fitted 192×144, pad y = 24.
    func testLetterboxGeometryForLandscape() {
        let lb = Letterbox(imageWidth: 640, imageHeight: 480, modelSize: 192)
        XCTAssertEqual(lb.ratio, 0.3, accuracy: 1e-9)
        XCTAssertEqual(lb.padX, 0, accuracy: 1e-9)
        XCTAssertEqual(lb.padY, 24, accuracy: 1e-9) // (192 - 480*0.3)/2 = (192-144)/2
    }

    func testLetterboxCentreMapsToImageCentre() {
        let lb = Letterbox(imageWidth: 640, imageHeight: 480, modelSize: 192)
        let c = lb.imageNormalized(CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(c.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(c.y, 0.5, accuracy: 1e-9)
    }

    func testLetterboxUndoesPadding() {
        let lb = Letterbox(imageWidth: 640, imageHeight: 480, modelSize: 192)
        // Top of the fitted region (y = pad/192) maps to image y = 0.
        let topNorm = lb.padY / 192
        XCTAssertEqual(lb.imageNormalized(CGPoint(x: 0.5, y: topNorm)).y, 0, accuracy: 1e-9)
        // Bottom of the fitted region maps to image y = 1.
        let bottomNorm = 1 - lb.padY / 192
        XCTAssertEqual(lb.imageNormalized(CGPoint(x: 0.5, y: bottomNorm)).y, 1, accuracy: 1e-9)
    }

    func testSquareImageIsIdentity() {
        let lb = Letterbox(imageWidth: 200, imageHeight: 200, modelSize: 192)
        XCTAssertEqual(lb.padX, 0, accuracy: 1e-9)
        XCTAssertEqual(lb.padY, 0, accuracy: 1e-9)
        let p = lb.imageNormalized(CGPoint(x: 0.3, y: 0.7))
        XCTAssertEqual(p.x, 0.3, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.7, accuracy: 1e-9)
    }

    func testHandLandmarkDecodeNormalizesByInputSize() throws {
        var raw = [Float](repeating: 0, count: 63)
        raw[0] = 112; raw[1] = 56 // landmark 0 at (112, 56) in 224 space
        let result = try XCTUnwrap(HandLandmarkDecode.result(landmarks: raw, presence: 0.9, modelInput: 224))
        XCTAssertEqual(result.points.count, 21)
        XCTAssertEqual(result.points[0].x, 0.5, accuracy: 1e-9)   // 112/224
        XCTAssertEqual(result.points[0].y, 0.25, accuracy: 1e-9)  // 56/224
        XCTAssertEqual(result.presence, 0.9, accuracy: 1e-6) // Float→Double
    }

    func testHandLandmarkDecodeRejectsShortOutput() {
        XCTAssertNil(HandLandmarkDecode.result(landmarks: [1, 2, 3], presence: 0.9, modelInput: 224))
    }
}
