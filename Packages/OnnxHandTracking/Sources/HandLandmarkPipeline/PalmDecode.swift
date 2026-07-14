import CoreGraphics
import Foundation

/// A decoded palm candidate in **letterbox-square normalized** coordinates
/// (the model's 192×192 input as a [0,1] square; the caller maps this back to
/// the real image using the letterbox ratio/pad). Carries the 7 palm
/// landmarks the landmark stage needs for the rotation-aligned crop.
public struct PalmCandidate: Equatable, Sendable {
    public var box: CGRect
    public var palmLandmarks: [CGPoint] // 7
    public var score: Double

    public init(box: CGRect, palmLandmarks: [CGPoint], score: Double) {
        self.box = box
        self.palmLandmarks = palmLandmarks
        self.score = score
    }
}

/// Decodes BlazePalm's raw SSD outputs, mirroring the OpenCV Zoo reference
/// (`mp_palmdet.py`): sigmoid the per-anchor scores, add the anchor centre to
/// the box/landmark deltas (normalized by the 192 input), then non-max
/// suppress. Pure and deterministic.
public enum PalmDecode {
    /// - Parameters:
    ///   - scores: 2016 raw logits (`Identity_1`).
    ///   - regression: 2016×18 = [cx,cy,w,h, then 7×(x,y)] deltas (`Identity`).
    ///   - anchors: flat [cx0,cy0,…], 4032 values (`PalmAnchors.flat`).
    ///   - modelInput: the model's square input side (192).
    public static func candidates(
        scores: [Float],
        regression: [Float],
        anchors: [Float] = PalmAnchors.flat,
        modelInput: Double,
        scoreThreshold: Double
    ) -> [PalmCandidate] {
        let count = min(scores.count, anchors.count / 2, regression.count / 18)
        var out: [PalmCandidate] = []
        for i in 0..<count {
            let score = 1.0 / (1.0 + exp(-Double(scores[i])))
            guard score >= scoreThreshold else { continue }

            let ax = Double(anchors[2 * i]), ay = Double(anchors[2 * i + 1])
            let r = 18 * i
            let cx = Double(regression[r + 0]) / modelInput + ax
            let cy = Double(regression[r + 1]) / modelInput + ay
            let w = Double(regression[r + 2]) / modelInput
            let h = Double(regression[r + 3]) / modelInput
            let box = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)

            var landmarks: [CGPoint] = []
            landmarks.reserveCapacity(7)
            for k in 0..<7 {
                let lx = Double(regression[r + 4 + 2 * k]) / modelInput + ax
                let ly = Double(regression[r + 4 + 2 * k + 1]) / modelInput + ay
                landmarks.append(CGPoint(x: lx, y: ly))
            }
            out.append(PalmCandidate(box: box, palmLandmarks: landmarks, score: score))
        }
        return out
    }

    /// Greedy non-maximum suppression by box IoU, highest score first.
    public static func nonMaxSuppressed(_ candidates: [PalmCandidate], iouThreshold: Double) -> [PalmCandidate] {
        let sorted = candidates.sorted { $0.score > $1.score }
        var kept: [PalmCandidate] = []
        for candidate in sorted where !kept.contains(where: { iou($0.box, candidate.box) > iouThreshold }) {
            kept.append(candidate)
        }
        return kept
    }

    /// The best (highest-score) non-suppressed palm, or nil.
    public static func best(
        scores: [Float],
        regression: [Float],
        anchors: [Float] = PalmAnchors.flat,
        modelInput: Double,
        scoreThreshold: Double,
        iouThreshold: Double
    ) -> PalmCandidate? {
        nonMaxSuppressed(
            candidates(scores: scores, regression: regression, anchors: anchors,
                       modelInput: modelInput, scoreThreshold: scoreThreshold),
            iouThreshold: iouThreshold
        ).max { $0.score < $1.score }
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        guard !inter.isNull else { return 0 }
        let interArea = inter.width * inter.height
        let union = a.width * a.height + b.width * b.height - interArea
        return union > 0 ? interArea / union : 0
    }
}
