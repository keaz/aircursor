import CoreGraphics

/// Pure geometry for the crop the landmark model runs on, in image-normalized
/// coordinates (top-left origin, unit square).
///
/// The crop is square in **pixels** (equal real extent per axis), not in
/// normalized space, so resizing it to the model's square input is a uniform
/// scale with no aspect distortion — measured to matter: a 16:9 camera's
/// normalized-square crop stretches the hand ~1.8× and the landmark model
/// loses confidence. The crop→image inverse below is per-axis linear, so it
/// stays correct for the resulting non-square (in normalized space) rect.
public enum HandCropGeometry {
    /// A crop centred on `box`, square in pixels for an image of the given
    /// `aspect` (imageWidth / imageHeight), enlarged by `scale` and clamped
    /// inside the unit square. Enlarged because the landmark model expects the
    /// hand with margin (MediaPipe uses ~2.6× the palm box). `aspect == 1`
    /// reduces to a plain normalized square.
    public static func squareCrop(around box: CGRect, scale: Double, aspect: Double = 1.0) -> CGRect {
        // Work in vertical-normalized units. The pixel-square side, expressed as
        // a fraction of image height, is max(box.width·aspect, box.height)·scale;
        // clamp so neither normalized dimension exceeds 1 (widthNorm = sideH/aspect).
        let sideH = min(min(1.0, aspect), max(box.width * aspect, box.height, 1e-4) * scale)
        let heightNorm = sideH
        let widthNorm = sideH / aspect
        let x = min(max(0, box.midX - widthNorm / 2), 1 - widthNorm)
        let y = min(max(0, box.midY - heightNorm / 2), 1 - heightNorm)
        return CGRect(x: x, y: y, width: widthNorm, height: heightNorm)
    }

    /// The bounding box of `points`, or nil if empty. Used to re-crop from the
    /// previous frame's landmarks while following a hand.
    public static func boundingBox(of points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Maps a crop-normalized point (the landmark model's output, in [0,1]
    /// relative to `crop`) back to image-normalized coordinates.
    public static func imagePoint(fromCropNormalized p: CGPoint, crop: CGRect) -> CGPoint {
        CGPoint(x: crop.minX + p.x * crop.width, y: crop.minY + p.y * crop.height)
    }

    /// Maps all of a landmark model's crop-normalized outputs back to the
    /// full image.
    public static func imagePoints(fromCropNormalized points: [CGPoint], crop: CGRect) -> [CGPoint] {
        points.map { imagePoint(fromCropNormalized: $0, crop: crop) }
    }
}
