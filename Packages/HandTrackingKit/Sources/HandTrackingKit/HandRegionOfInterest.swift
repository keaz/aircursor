import CoreGraphics

/// Pure geometry for ROI track-following. Once a hand is found, the next
/// Vision search is constrained to the inflated bounding box of that hand,
/// so the detector follows the hand instead of re-scanning the whole frame
/// (where a cluttered background can win). Coordinates are Vision's
/// normalized image space (unit square).
enum HandRegionOfInterest {
    /// The whole frame — used on cold start and after a detection loss.
    static let full = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// The next region: the bounding box of `points`, inflated by `factor`
    /// about its centre and clamped to the unit square. `full` if empty.
    static func next(fromNormalizedPoints points: [CGPoint], inflateBy factor: Double) -> CGRect {
        guard !points.isEmpty else { return full }
        let xs = points.map(\.x), ys = points.map(\.y)
        let box = CGRect(
            x: xs.min()!, y: ys.min()!,
            width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!
        )
        return inflate(box, by: factor)
    }

    /// Inflates a box about its centre and clamps it inside the unit square.
    /// A degenerate (zero-size) box is given a small floor so the result is
    /// always a usable region.
    static func inflate(_ box: CGRect, by factor: Double) -> CGRect {
        let floor = 0.02
        let w = min(1.0, max(box.width, floor) * factor)
        let h = min(1.0, max(box.height, floor) * factor)
        let x = max(0, min(box.midX - w / 2, 1 - w))
        let y = max(0, min(box.midY - h / 2, 1 - h))
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
