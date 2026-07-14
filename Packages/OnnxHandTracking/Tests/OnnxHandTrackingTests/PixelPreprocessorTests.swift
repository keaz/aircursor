import CoreGraphics
import CoreVideo
import Foundation
@testable import OnnxHandTracking
import XCTest

final class PixelPreprocessorTests: XCTestCase {
    /// Builds a BGRA pixel buffer, top half one colour, bottom half another,
    /// so the tensor's orientation (top-left) and channel order (RGB) are
    /// verifiable.
    private func twoTonePixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &pb)
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let p = base + y * stride + x * 4
                // BGRA byte order. Top half red, bottom half blue.
                let red = y < height / 2
                p[0] = red ? 0 : 255   // B
                p[1] = 0               // G
                p[2] = red ? 255 : 0   // R
                p[3] = 255             // A
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    func testLetterboxTensorKeepsTopLeftOrientationAndRGBOrder() throws {
        let pb = twoTonePixelBuffer(width: 224, height: 224) // square → no padding
        let pre = PixelPreprocessor()
        let size = 192
        let tensor = try XCTUnwrap(pre.letterboxTensor(from: pb, size: size))
        XCTAssertEqual(tensor.count, size * size * 3)

        func rgb(_ x: Int, _ y: Int) -> (Float, Float, Float) {
            let i = (y * size + x) * 3
            return (tensor[i], tensor[i + 1], tensor[i + 2])
        }
        // Top row is red (R≈1, B≈0); bottom row is blue (R≈0, B≈1).
        let top = rgb(size / 2, 5)
        XCTAssertGreaterThan(top.0, 0.8, "top is red → high R")
        XCTAssertLessThan(top.2, 0.2, "top is red → low B")
        let bottom = rgb(size / 2, size - 5)
        XCTAssertLessThan(bottom.0, 0.2, "bottom is blue → low R")
        XCTAssertGreaterThan(bottom.2, 0.8, "bottom is blue → high B")
    }

    func testCropTensorSelectsTheRequestedRegion() throws {
        let pb = twoTonePixelBuffer(width: 224, height: 224)
        let pre = PixelPreprocessor()
        let size = 224
        // Crop the top half → should be entirely red.
        let tensor = try XCTUnwrap(pre.cropTensor(
            from: pb, crop: CGRect(x: 0, y: 0, width: 1, height: 0.5), size: size
        ))
        func rgb(_ x: Int, _ y: Int) -> (Float, Float, Float) {
            let i = (y * size + x) * 3
            return (tensor[i], tensor[i + 1], tensor[i + 2])
        }
        for y in stride(from: 10, to: size, by: 40) {
            let c = rgb(size / 2, y)
            XCTAssertGreaterThan(c.0, 0.8, "top-half crop is all red at y=\(y)")
            XCTAssertLessThan(c.2, 0.2)
        }
    }

    func testLetterboxPadsNonSquareWithBlack() throws {
        let pb = twoTonePixelBuffer(width: 224, height: 112) // 2:1 → vertical pad
        let pre = PixelPreprocessor()
        let size = 192
        let tensor = try XCTUnwrap(pre.letterboxTensor(from: pb, size: size))
        // Very top and bottom rows are padding → black.
        func rgb(_ x: Int, _ y: Int) -> (Float, Float, Float) {
            let i = (y * size + x) * 3
            return (tensor[i], tensor[i + 1], tensor[i + 2])
        }
        let padTop = rgb(size / 2, 1)
        XCTAssertLessThan(padTop.0 + padTop.1 + padTop.2, 0.1, "letterbox pad is black")
    }
}
