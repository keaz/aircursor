import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import HandLandmarkPipeline

/// Converts camera pixel buffers into the float32 NHWC RGB tensors the ONNX
/// models expect: values in [0,1], top-left origin, row-major, channel order
/// R,G,B. Uses CoreGraphics so orientation and channel order are
/// deterministic (CoreImage-only paths are y-flip-ambiguous).
struct PixelPreprocessor {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Aspect-preserving letterbox of the whole frame into `size`×`size`,
    /// padded black — for the palm detector (192).
    func letterboxTensor(from pixelBuffer: CVPixelBuffer, size: Int) -> [Float]? {
        guard let cg = cgImage(from: pixelBuffer) else { return nil }
        let lb = Letterbox(imageWidth: Double(cg.width), imageHeight: Double(cg.height), modelSize: Double(size))
        let f = lb.fittedRect
        let dest = CGRect(
            x: f.minX * Double(size), y: f.minY * Double(size),
            width: f.width * Double(size), height: f.height * Double(size)
        )
        return tensor(from: cg, cropPixels: nil, dest: dest, size: size)
    }

    /// Crop `crop` (image-normalized, top-left origin) and resize to
    /// `size`×`size` — for the landmark model (224).
    func cropTensor(from pixelBuffer: CVPixelBuffer, crop: CGRect, size: Int) -> [Float]? {
        guard let cg = cgImage(from: pixelBuffer) else { return nil }
        let w = Double(cg.width), h = Double(cg.height)
        let cropPixels = CGRect(x: crop.minX * w, y: crop.minY * h, width: crop.width * w, height: crop.height * h)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !cropPixels.isNull, cropPixels.width >= 1, cropPixels.height >= 1 else { return nil }
        return tensor(from: cg, cropPixels: cropPixels, dest: CGRect(x: 0, y: 0, width: size, height: size), size: size)
    }

    private func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ci, from: ci.extent)
    }

    /// Draws `source` (optionally cropped, in top-left pixel coords) into
    /// `dest` of a black `size`×`size` RGBA canvas, then reads RGB floats.
    private func tensor(from source: CGImage, cropPixels: CGRect?, dest: CGRect, size: Int) -> [Float]? {
        let bytesPerRow = size * 4
        let data = UnsafeMutableRawPointer.allocate(byteCount: size * bytesPerRow, alignment: 16)
        defer { data.deallocate() }
        data.initializeMemory(as: UInt8.self, repeating: 0, count: size * bytesPerRow)

        guard let ctx = CGContext(
            data: data, width: size, height: size, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // A CGBitmapContext lays out memory row 0 = top of the image, and
        // ctx.draw renders a CGImage upright, so the buffer is already
        // top-left. Read rows in order (measured: any extra flip inverts it).
        ctx.interpolationQuality = .high
        let image = cropPixels.flatMap { source.cropping(to: $0) } ?? source
        ctx.draw(image, in: dest)

        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var out = [Float](repeating: 0, count: size * size * 3)
        for i in 0..<(size * size) {
            out[3 * i + 0] = Float(bytes[4 * i + 0]) / 255 // R
            out[3 * i + 1] = Float(bytes[4 * i + 1]) / 255 // G
            out[3 * i + 2] = Float(bytes[4 * i + 2]) / 255 // B
        }
        return out
    }
}
