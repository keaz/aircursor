import CoreGraphics
import Foundation

/// Aspect-preserving fit of an image into a square model input (the palm
/// detector's 192×192), with symmetric padding. Maps points between the
/// letterbox-square normalized space the model/decode use and the original
/// image's normalized space. Mirrors the OpenCV Zoo preprocessing.
public struct Letterbox: Equatable, Sendable {
    public let modelSize: Double
    public let imageWidth: Double
    public let imageHeight: Double
    /// Scale applied to the image so its longer side fits `modelSize`.
    public let ratio: Double
    /// Symmetric padding on each axis, in model pixels.
    public let padX: Double
    public let padY: Double

    public init(imageWidth: Double, imageHeight: Double, modelSize: Double) {
        precondition(imageWidth > 0 && imageHeight > 0 && modelSize > 0)
        self.modelSize = modelSize
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.ratio = min(modelSize / imageWidth, modelSize / imageHeight)
        self.padX = (modelSize - imageWidth * ratio) / 2
        self.padY = (modelSize - imageHeight * ratio) / 2
    }

    /// The image's fitted rectangle within the square, in the square's
    /// normalized [0,1] coordinates. Preprocessing draws the scaled image here
    /// on a black background.
    public var fittedRect: CGRect {
        CGRect(
            x: padX / modelSize, y: padY / modelSize,
            width: imageWidth * ratio / modelSize, height: imageHeight * ratio / modelSize
        )
    }

    /// Letterbox-square normalized point → original-image normalized point.
    public func imageNormalized(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: (p.x * modelSize - padX) / (imageWidth * ratio),
            y: (p.y * modelSize - padY) / (imageHeight * ratio)
        )
    }

    /// Maps a whole rect from letterbox-square normalized to image normalized.
    public func imageNormalized(_ rect: CGRect) -> CGRect {
        let o = imageNormalized(rect.origin)
        let e = imageNormalized(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: o.x, y: o.y, width: e.x - o.x, height: e.y - o.y)
    }
}
