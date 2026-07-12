import CoreGraphics
import Foundation

/// The One Euro filter (Casiez, Roussel, Vogel — CHI 2012): an adaptive
/// first-order low-pass whose cutoff rises with signal speed, so a stationary
/// hand is heavily smoothed (no jitter) while a fast hand tracks with little
/// lag.
///
/// Standard formulation, real-dt aware: τ = 1/(2π·cutoff),
/// α = 1/(1 + τ/dt), cutoff = minCutoff + beta·|dx̂|, with the derivative
/// itself low-passed at `dCutoff`.
public struct OneEuroFilter: Sendable {
    /// Cutoff frequency (Hz) at rest. Lower → smoother but laggier.
    public var minCutoff: Double
    /// Velocity coefficient. Higher → faster motions cut through with less lag.
    public var beta: Double
    /// Cutoff (Hz) for the derivative estimate's own low-pass.
    public var dCutoff: Double

    private var previousValue: Double?
    private var previousDerivative = 0.0
    private var previousTimestamp: TimeInterval?

    public init(minCutoff: Double = 1.0, beta: Double = 0.0, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    /// Filters one sample. The first sample (or the first after `reset()`)
    /// passes through unchanged. A sample whose timestamp does not advance is
    /// ignored: the previous output is returned and state is untouched.
    public mutating func filter(_ value: Double, at timestamp: TimeInterval) -> Double {
        guard let lastValue = previousValue, let lastTimestamp = previousTimestamp else {
            previousValue = value
            previousDerivative = 0
            previousTimestamp = timestamp
            return value
        }

        let dt = timestamp - lastTimestamp
        guard dt > 0 else { return lastValue }

        let derivative = (value - lastValue) / dt
        let smoothedDerivative = lowPass(
            derivative, previous: previousDerivative, alpha: alpha(cutoff: dCutoff, dt: dt)
        )
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let smoothedValue = lowPass(
            value, previous: lastValue, alpha: alpha(cutoff: cutoff, dt: dt)
        )

        previousValue = smoothedValue
        previousDerivative = smoothedDerivative
        previousTimestamp = timestamp
        return smoothedValue
    }

    public mutating func reset() {
        previousValue = nil
        previousDerivative = 0
        previousTimestamp = nil
    }

    private func alpha(cutoff: Double, dt: TimeInterval) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    private func lowPass(_ value: Double, previous: Double, alpha: Double) -> Double {
        alpha * value + (1 - alpha) * previous
    }
}

/// Two `OneEuroFilter`s, one per axis.
public struct PointOneEuroFilter: Sendable {
    private var xFilter: OneEuroFilter
    private var yFilter: OneEuroFilter

    public init(minCutoff: Double = 1.0, beta: Double = 0.0, dCutoff: Double = 1.0) {
        self.xFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
        self.yFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
    }

    public mutating func filter(_ point: CGPoint, at timestamp: TimeInterval) -> CGPoint {
        CGPoint(
            x: xFilter.filter(point.x, at: timestamp),
            y: yFilter.filter(point.y, at: timestamp)
        )
    }

    public mutating func reset() {
        xFilter.reset()
        yFilter.reset()
    }
}
