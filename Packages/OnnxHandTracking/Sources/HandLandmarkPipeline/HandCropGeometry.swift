import CoreGraphics

/// Pure geometry for the crop the landmark model runs on, in image-normalized
/// coordinates (top-left origin, unit square).
///
/// v1 works entirely in normalized space with a plain linear crop→model
/// resize (the inverse below assumes that). Aspect-preserving padding to the
/// model's square input is an O2 refinement; a mild aspect stretch is
/// tolerated by the landmark model.
public enum HandCropGeometry {
    /// A square (in normalized space) crop centred on `box`, enlarged by
    /// `scale` and clamped inside the unit square. Enlarged because the
    /// landmark model expects the hand with margin (MediaPipe uses ~2.6× the
    /// palm box).
    public static func squareCrop(around box: CGRect, scale: Double) -> CGRect {
        let side = min(1.0, max(box.width, box.height, 1e-4) * scale)
        let x = min(max(0, box.midX - side / 2), 1 - side)
        let y = min(max(0, box.midY - side / 2), 1 - side)
        return CGRect(x: x, y: y, width: side, height: side)
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
