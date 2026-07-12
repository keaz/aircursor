import CoreGraphics
import Foundation
import HandPoseCore

/// Deterministic pseudo-random numbers for synthetic jitter (SplitMix64).
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unitDouble() -> Double {
        Double(next() >> 11) * (1.0 / Double(1 << 53))
    }

    /// Uniform in [-magnitude, +magnitude].
    mutating func jitter(_ magnitude: Double) -> Double {
        (unitDouble() * 2 - 1) * magnitude
    }
}

/// Builds synthetic hand poses for fixtures. Geometry is anatomy-flavored;
/// exact realism only matters for the joints the pipeline consumes: wrist and
/// middleMCP (the pinch normalizer), thumbTip, indexTip, middleTip.
enum SyntheticHand {
    /// Wrist–middleMCP distance, the pinch-metric normalizer.
    static let handSpan: Double = 0.2

    /// A full 21-joint pose. Pinch ratios are tip-to-tip distance divided by
    /// `handSpan`, matching the engine's normalized pinch metric.
    static func joints(
        center: CGPoint = CGPoint(x: 0.5, y: 0.55),
        thumbIndexRatio: Double,
        thumbMiddleRatio: Double = 1.1
    ) -> [HandJoint: CGPoint] {
        let wrist = CGPoint(x: center.x, y: center.y + 0.25)
        let middleMCP = CGPoint(x: wrist.x, y: wrist.y - handSpan)

        let thumbTip = CGPoint(x: center.x - 0.04, y: center.y)
        let indexTip = point(from: thumbTip, distance: thumbIndexRatio * handSpan, angle: -.pi / 3)
        let middleTip = point(from: thumbTip, distance: thumbMiddleRatio * handSpan, angle: -.pi / 2.4)

        let indexMCP = CGPoint(x: middleMCP.x - 0.045, y: middleMCP.y + 0.01)
        let ringMCP = CGPoint(x: middleMCP.x + 0.045, y: middleMCP.y + 0.01)
        let littleMCP = CGPoint(x: middleMCP.x + 0.085, y: middleMCP.y + 0.03)
        let thumbCMC = CGPoint(x: wrist.x - 0.05, y: wrist.y - 0.05)

        let ringTip = CGPoint(x: ringMCP.x + 0.02, y: ringMCP.y - 0.16)
        let littleTip = CGPoint(x: littleMCP.x + 0.03, y: littleMCP.y - 0.13)

        var joints: [HandJoint: CGPoint] = [
            .wrist: wrist,
            .middleMCP: middleMCP,
            .thumbCMC: thumbCMC,
            .thumbTip: thumbTip,
            .indexMCP: indexMCP,
            .indexTip: indexTip,
            .middleTip: middleTip,
            .ringMCP: ringMCP,
            .ringTip: ringTip,
            .littleMCP: littleMCP,
            .littleTip: littleTip,
        ]

        // Intermediate joints interpolated along each finger chain.
        joints[.thumbMP] = lerp(thumbCMC, thumbTip, 0.45)
        joints[.thumbIP] = lerp(thumbCMC, thumbTip, 0.75)
        joints[.indexPIP] = lerp(indexMCP, indexTip, 0.45)
        joints[.indexDIP] = lerp(indexMCP, indexTip, 0.75)
        joints[.middlePIP] = lerp(middleMCP, middleTip, 0.45)
        joints[.middleDIP] = lerp(middleMCP, middleTip, 0.75)
        joints[.ringPIP] = lerp(ringMCP, ringTip, 0.45)
        joints[.ringDIP] = lerp(ringMCP, ringTip, 0.75)
        joints[.littlePIP] = lerp(littleMCP, littleTip, 0.45)
        joints[.littleDIP] = lerp(littleMCP, littleTip, 0.75)
        return joints
    }

    private static func point(from origin: CGPoint, distance: Double, angle: Double) -> CGPoint {
        CGPoint(x: origin.x + distance * cos(angle), y: origin.y + distance * sin(angle))
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

/// Frame-sequence builder with a running camera-clock timestamp.
struct FrameSequenceBuilder {
    private(set) var frames: [HandPoseFrame] = []
    private var timestamp: TimeInterval = 0
    let dt: TimeInterval

    init(fps: Double = 60) {
        self.dt = 1 / fps
    }

    mutating func append(joints: [HandJoint: CGPoint]) {
        frames.append(HandPoseFrame(joints: joints, timestamp: timestamp))
        timestamp += dt
    }

    mutating func appendHandLost() {
        append(joints: [:])
    }
}

enum FixtureLocations {
    /// `<repo>/Fixtures`, resolved relative to this source file.
    static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // HandTrackingKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // HandTrackingKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Fixtures", isDirectory: true)
    }
}
