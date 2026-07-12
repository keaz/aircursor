/// A mild velocity-dependent gain: slow hand → precision, fast hand → travel.
///
/// g(v) = 1 + (maxGain − 1) · v² / (v² + halfSpeed²) — exactly 1 at rest,
/// half the boost at `halfSpeed`, saturating smoothly toward `maxGain`.
/// Speeds are in normalized hand-space units per second.
public struct VelocityGainCurve: Equatable, Sendable {
    /// Upper gain bound as speed grows; 1 disables velocity gain entirely.
    public var maxGain: Double
    /// Speed at which half of the extra gain applies.
    public var halfSpeed: Double

    public init(maxGain: Double = 2.0, halfSpeed: Double = 1.0) {
        precondition(maxGain >= 1, "maxGain below 1 would invert the curve")
        precondition(halfSpeed > 0, "halfSpeed must be positive")
        self.maxGain = maxGain
        self.halfSpeed = halfSpeed
    }

    public func gain(forSpeed speed: Double) -> Double {
        let v2 = speed * speed
        return 1 + (maxGain - 1) * v2 / (v2 + halfSpeed * halfSpeed)
    }
}
