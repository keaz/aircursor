import CoreGraphics
@testable import HandTrackingKit
import XCTest

/// Pure geometry for ROI track-following: the next search region is the
/// inflated bounding box of the last hand, clamped to the unit square.
final class HandRegionOfInterestTests: XCTestCase {
    func testNoPointsGivesFullFrame() {
        XCTAssertEqual(HandRegionOfInterest.next(fromNormalizedPoints: [], inflateBy: 2.5),
                       HandRegionOfInterest.full)
    }

    func testInflatesBoundingBoxAroundItsCentre() {
        let points = [CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.6, y: 0.6)] // box 0.2×0.2 centred at 0.5
        let roi = HandRegionOfInterest.next(fromNormalizedPoints: points, inflateBy: 2.0)
        XCTAssertEqual(roi.midX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(roi.midY, 0.5, accuracy: 1e-9)
        XCTAssertEqual(roi.width, 0.4, accuracy: 1e-9)
        XCTAssertEqual(roi.height, 0.4, accuracy: 1e-9)
    }

    func testClampsToUnitSquareNearAnEdge() {
        let points = [CGPoint(x: 0.02, y: 0.5), CGPoint(x: 0.08, y: 0.5)] // near the left edge
        let roi = HandRegionOfInterest.next(fromNormalizedPoints: points, inflateBy: 3.0)
        XCTAssertGreaterThanOrEqual(roi.minX, 0)
        XCTAssertLessThanOrEqual(roi.maxX, 1)
        XCTAssertGreaterThanOrEqual(roi.minY, 0)
        XCTAssertLessThanOrEqual(roi.maxY, 1)
    }

    func testLargeInflationSaturatesToFullFrameDimension() {
        let points = [CGPoint(x: 0.45, y: 0.45), CGPoint(x: 0.55, y: 0.55)]
        let roi = HandRegionOfInterest.next(fromNormalizedPoints: points, inflateBy: 100)
        XCTAssertLessThanOrEqual(roi.width, 1.0)
        XCTAssertLessThanOrEqual(roi.height, 1.0)
        XCTAssertGreaterThanOrEqual(roi.minX, 0)
        XCTAssertLessThanOrEqual(roi.maxX, 1)
    }

    func testDegenerateSinglePointBoxStillProducesAValidRegion() {
        let roi = HandRegionOfInterest.next(fromNormalizedPoints: [CGPoint(x: 0.5, y: 0.5)], inflateBy: 2.5)
        XCTAssertGreaterThan(roi.width, 0)
        XCTAssertGreaterThan(roi.height, 0)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(roi))
    }
}
