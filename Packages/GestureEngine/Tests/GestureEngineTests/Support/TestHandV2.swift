import CoreGraphics
import Foundation
import HandPoseCore

/// v2 test hand with per-finger extension control. Each finger is built
/// colinearly from the wrist, so its extension ratio
/// dist(tip, wrist) / dist(pip, wrist) is exact by construction; the
/// thumb–index pinch ratio is likewise exact against the 0.2 wrist–middleMCP
/// span. All joints translate rigidly with `center`.
enum TestHandV2 {
    static let span = 0.2
    static let extendedRatio = 1.4
    static let curledRatio = 0.55

    struct Fingers {
        var index: Double
        var middle: Double
        var ring: Double
        var little: Double

        init(
            index: Bool = false, middle: Bool = false,
            ring: Bool = false, little: Bool = false
        ) {
            self.index = index ? extendedRatio : curledRatio
            self.middle = middle ? extendedRatio : curledRatio
            self.ring = ring ? extendedRatio : curledRatio
            self.little = little ? extendedRatio : curledRatio
        }

        init(index: Double, middle: Double, ring: Double, little: Double) {
            self.index = index
            self.middle = middle
            self.ring = ring
            self.little = little
        }
    }

    /// - Parameters:
    ///   - fingers: per-finger extension ratios (or bools via `Fingers`).
    ///   - indexPinch: thumb–index distance / span; nil places the thumb a
    ///     full span away (ratio 1.0).
    static func joints(
        center: CGPoint = CGPoint(x: 0.5, y: 0.55),
        fingers: Fingers,
        indexPinch: Double? = nil
    ) -> [HandJoint: CGPoint] {
        let wrist = CGPoint(x: center.x, y: center.y + 0.25)

        func ray(_ degrees: Double) -> CGVector {
            let radians = degrees * .pi / 180
            return CGVector(dx: cos(radians), dy: sin(radians))
        }
        // Upward fan (hand-space y grows downward, so "up" is negative y).
        let rays: [(HandJoint, HandJoint, HandJoint, CGVector, Double)] = [
            (.indexMCP, .indexPIP, .indexTip, ray(-104), fingers.index),
            (.middleMCP, .middlePIP, .middleTip, ray(-90), fingers.middle),
            (.ringMCP, .ringPIP, .ringTip, ray(-76), fingers.ring),
            (.littleMCP, .littlePIP, .littleTip, ray(-62), fingers.little),
        ]

        var joints: [HandJoint: CGPoint] = [.wrist: wrist]
        let pipDistance = 0.25
        for (mcp, pip, tip, direction, ratio) in rays {
            joints[mcp] = point(from: wrist, along: direction, distance: span)
            joints[pip] = point(from: wrist, along: direction, distance: pipDistance)
            joints[tip] = point(from: wrist, along: direction, distance: pipDistance * ratio)
        }

        // Thumb: placed relative to the index tip so the pinch ratio is exact.
        let indexTip = joints[.indexTip]!
        let pinchRatio = indexPinch ?? 1.0
        let thumbDirection = ray(160)
        joints[.thumbTip] = point(
            from: indexTip, along: thumbDirection, distance: pinchRatio * span
        )
        joints[.thumbCMC] = CGPoint(x: wrist.x - 0.05, y: wrist.y - 0.04)
        joints[.thumbMP] = CGPoint(x: wrist.x - 0.08, y: wrist.y - 0.09)
        joints[.thumbIP] = CGPoint(x: wrist.x - 0.10, y: wrist.y - 0.13)
        return joints
    }

    private static func point(
        from origin: CGPoint, along direction: CGVector, distance: Double
    ) -> CGPoint {
        CGPoint(x: origin.x + direction.dx * distance, y: origin.y + direction.dy * distance)
    }
}
