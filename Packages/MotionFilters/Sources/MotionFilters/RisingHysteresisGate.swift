/// The rising-polarity twin of `HysteresisGate`: engages when the value
/// rises strictly above `engageThreshold`, releases when it falls strictly
/// below `releaseThreshold` (engage > release). Used for finger-extension
/// detection, where "on" means a large tip-to-wrist ratio.
public struct RisingHysteresisGate: Sendable {
    public let engageThreshold: Double
    public let releaseThreshold: Double
    public private(set) var isEngaged = false

    public init(engageThreshold: Double, releaseThreshold: Double) {
        precondition(
            engageThreshold > releaseThreshold,
            "hysteresis requires engageThreshold > releaseThreshold"
        )
        self.engageThreshold = engageThreshold
        self.releaseThreshold = releaseThreshold
    }

    /// Feeds one sample and returns the resulting state.
    @discardableResult
    public mutating func update(_ value: Double) -> Bool {
        if isEngaged {
            if value < releaseThreshold {
                isEngaged = false
            }
        } else {
            if value > engageThreshold {
                isEngaged = true
            }
        }
        return isEngaged
    }

    public mutating func reset() {
        isEngaged = false
    }
}
