import CoreGraphics
import HandLandmarkPipeline
import XCTest

final class HandCropGeometryTests: XCTestCase {
    func testSquareCropIsCentredAndScaled() {
        let box = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.1) // centre (0.5, 0.45)
        let crop = HandCropGeometry.squareCrop(around: box, scale: 2.0)
        // Side = max(0.2, 0.1) * 2 = 0.4, square.
        XCTAssertEqual(crop.width, 0.4, accuracy: 1e-9)
        XCTAssertEqual(crop.height, 0.4, accuracy: 1e-9)
        XCTAssertEqual(crop.midX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(crop.midY, 0.45, accuracy: 1e-9)
    }

    func testSquareCropClampsToUnitSquare() {
        let box = CGRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1) // centre near corner
        let crop = HandCropGeometry.squareCrop(around: box, scale: 4.0)
        XCTAssertGreaterThanOrEqual(crop.minX, 0)
        XCTAssertGreaterThanOrEqual(crop.minY, 0)
        XCTAssertLessThanOrEqual(crop.maxX, 1.0 + 1e-9)
        XCTAssertLessThanOrEqual(crop.maxY, 1.0 + 1e-9)
    }

    func testBoundingBoxOfPoints() throws {
        let box = try XCTUnwrap(HandCropGeometry.boundingBox(of: [
            CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.6, y: 0.1), CGPoint(x: 0.4, y: 0.5),
        ]))
        XCTAssertEqual(box.minX, 0.2, accuracy: 1e-9)
        XCTAssertEqual(box.minY, 0.1, accuracy: 1e-9)
        XCTAssertEqual(box.width, 0.4, accuracy: 1e-9)
        XCTAssertEqual(box.height, 0.4, accuracy: 1e-9)
        XCTAssertNil(HandCropGeometry.boundingBox(of: []))
    }

    func testImagePointInvertsTheCrop() {
        let crop = CGRect(x: 0.24, y: 0.24, width: 0.52, height: 0.52)
        // Crop-space centre maps to the crop's image-space centre.
        XCTAssertEqual(
            HandCropGeometry.imagePoint(fromCropNormalized: CGPoint(x: 0.5, y: 0.5), crop: crop),
            CGPoint(x: 0.5, y: 0.5)
        )
        // Crop-space origin maps to the crop's origin.
        XCTAssertEqual(
            HandCropGeometry.imagePoint(fromCropNormalized: CGPoint(x: 0, y: 0), crop: crop),
            CGPoint(x: 0.24, y: 0.24)
        )
    }

    func testCropRoundTrip() {
        // A point in the image, expressed relative to a crop, must map back.
        let crop = CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.4)
        let imagePoint = CGPoint(x: 0.5, y: 0.4)
        let cropNorm = CGPoint(
            x: (imagePoint.x - crop.minX) / crop.width,
            y: (imagePoint.y - crop.minY) / crop.height
        )
        let back = HandCropGeometry.imagePoint(fromCropNormalized: cropNorm, crop: crop)
        XCTAssertEqual(back.x, imagePoint.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, imagePoint.y, accuracy: 1e-9)
    }
}
