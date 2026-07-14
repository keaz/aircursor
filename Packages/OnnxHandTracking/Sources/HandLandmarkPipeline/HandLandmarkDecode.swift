import CoreGraphics
import Foundation

/// Decodes the hand-landmark model's raw outputs. The model emits 21 (x,y,z)
/// screen landmarks in its **224×224 input-pixel** space plus a presence
/// score. Axis-aligned variant (no rotation): landmarks are simply
/// normalized by the input size to crop-space [0,1]; the pipeline then maps
/// them back to the image with the crop inverse.
public enum HandLandmarkDecode {
    /// - Parameters:
    ///   - landmarks: 63 floats = 21 × (x, y, z) in model-input pixels (`Identity`).
    ///   - presence: the raw `Identity_1` value (already a probability).
    ///   - modelInput: the landmark model's square input side (224).
    /// - Returns: 21 crop-normalized points + presence, or nil if malformed.
    public static func result(
        landmarks: [Float],
        presence: Float,
        modelInput: Double
    ) -> HandLandmarks? {
        guard landmarks.count >= 63 else { return nil }
        var points: [CGPoint] = []
        points.reserveCapacity(21)
        for i in 0..<21 {
            let x = Double(landmarks[3 * i]) / modelInput
            let y = Double(landmarks[3 * i + 1]) / modelInput
            points.append(CGPoint(x: x, y: y))
        }
        return HandLandmarks(points: points, presence: Double(presence))
    }
}
