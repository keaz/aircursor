/// A two-threshold gate for pinch detection: engages when the value drops
/// strictly below `closeThreshold`, releases when it rises strictly above
/// `openThreshold` (open > close). Values inside the band keep the current
/// state, so noise at a single boundary cannot flicker the gate.
public struct HysteresisGate: Sendable {
    public let closeThreshold: Double
    public let openThreshold: Double
    public private(set) var isEngaged = false

    public init(closeThreshold: Double, openThreshold: Double) {
        precondition(
            openThreshold > closeThreshold,
            "hysteresis requires openThreshold > closeThreshold"
        )
        self.closeThreshold = closeThreshold
        self.openThreshold = openThreshold
    }

    /// Feeds one sample and returns the resulting state.
    @discardableResult
    public mutating func update(_ value: Double) -> Bool {
        if isEngaged {
            if value > openThreshold {
                isEngaged = false
            }
        } else {
            if value < closeThreshold {
                isEngaged = true
            }
        }
        return isEngaged
    }

    public mutating func reset() {
        isEngaged = false
    }
}
