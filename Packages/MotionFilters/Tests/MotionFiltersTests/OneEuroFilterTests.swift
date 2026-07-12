import CoreGraphics
import Foundation
import MotionFilters
import XCTest

/// Analytic expectations for the standard One Euro formulation:
/// τ = 1/(2π·cutoff), α = 1/(1 + τ/dt), and with beta = 0 the filter is a
/// plain exponential moving average with cutoff = minCutoff.
final class OneEuroFilterTests: XCTestCase {
    private let dt = 1.0 / 60
    /// α for cutoff 1 Hz at 60 Hz sampling: 1/(1 + 60/(2π)).
    private let alpha1Hz60 = 1.0 / (1.0 + 60.0 / (2.0 * Double.pi))

    func testFirstSamplePassesThroughUnchanged() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0, dCutoff: 1)
        XCTAssertEqual(filter.filter(0.42, at: 0), 0.42)
    }

    func testStepResponseMatchesAnalyticAlpha() {
        // After seeding with 0, one sample of 1 must yield exactly α·1.
        var filter = OneEuroFilter(minCutoff: 1, beta: 0, dCutoff: 1)
        _ = filter.filter(0, at: 0)
        let output = filter.filter(1, at: dt)
        XCTAssertEqual(output, alpha1Hz60, accuracy: 1e-12)
    }

    func testConvergesToConstantInput() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0, dCutoff: 1)
        _ = filter.filter(0, at: 0)
        var output = 0.0
        for i in 1...61 {
            output = filter.filter(1, at: Double(i) * dt)
        }
        // Analytically 1 - (1-α)^61 ≈ 0.9977.
        XCTAssertGreaterThan(output, 0.99)
        XCTAssertLessThan(output, 1.0)
    }

    func testSuppressesJitterOnStationarySignal() {
        // Uniform noise ±0.05 around 0.5. White noise through this EMA keeps
        // ~sqrt(α/(2-α)) ≈ 22% of the input deviation; assert < 30%.
        var filter = OneEuroFilter(minCutoff: 1, beta: 0, dCutoff: 1)
        var generator = SeededGenerator(seed: 42)

        var rawTail: [Double] = []
        var filteredTail: [Double] = []
        for i in 0..<300 {
            let raw = 0.5 + generator.jitter(0.05)
            let filtered = filter.filter(raw, at: Double(i) * dt)
            if i >= 60 {
                rawTail.append(raw)
                filteredTail.append(filtered)
            }
        }

        XCTAssertLessThan(
            standardDeviation(filteredTail),
            0.3 * standardDeviation(rawTail),
            "filter should strongly attenuate stationary jitter"
        )
    }

    func testBetaReducesLagOnFastMotion() {
        // Ramp at 2 units/s for one second. The velocity term must track the
        // moving target more closely than the beta-less filter.
        var lazyFilter = OneEuroFilter(minCutoff: 1, beta: 0, dCutoff: 1)
        var adaptiveFilter = OneEuroFilter(minCutoff: 1, beta: 1, dCutoff: 1)

        var lazyError = 0.0
        var adaptiveError = 0.0
        for i in 0...60 {
            let t = Double(i) * dt
            let x = 2 * t
            lazyError = abs(lazyFilter.filter(x, at: t) - x)
            adaptiveError = abs(adaptiveFilter.filter(x, at: t) - x)
        }

        XCTAssertLessThan(adaptiveError, lazyError)
        XCTAssertGreaterThan(lazyError, 0, "a lagless EMA would make this test vacuous")
    }

    func testCutoffIsTimestampAwareNotSampleCountAware() {
        // A 1 s hold after a step must converge to (nearly) the same value
        // whether sampled at 60 Hz or 120 Hz.
        var at60 = OneEuroFilter(minCutoff: 1, beta: 0, dCutoff: 1)
        var at120 = OneEuroFilter(minCutoff: 1, beta: 0, dCutoff: 1)

        _ = at60.filter(0, at: 0)
        _ = at120.filter(0, at: 0)

        var out60 = 0.0
        for i in 1...60 {
            out60 = at60.filter(1, at: Double(i) / 60)
        }
        var out120 = 0.0
        for i in 1...120 {
            out120 = at120.filter(1, at: Double(i) / 120)
        }

        XCTAssertEqual(out60, out120, accuracy: 0.005)
    }

    func testNonIncreasingTimestampReturnsPreviousOutputUnchanged() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0, dCutoff: 1)
        let seeded = filter.filter(0.5, at: 1.0)
        // Same timestamp again: no dt to integrate over — output must not move.
        XCTAssertEqual(filter.filter(0.9, at: 1.0), seeded)
        // And the bogus sample must not have polluted state: the next valid
        // sample behaves as if it never happened.
        let next = filter.filter(1.0, at: 1.0 + dt)
        let expected = alpha1Hz60 * 1.0 + (1 - alpha1Hz60) * 0.5
        XCTAssertEqual(next, expected, accuracy: 1e-12)
    }

    func testResetForgetsHistory() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0, dCutoff: 1)
        _ = filter.filter(0.1, at: 0)
        _ = filter.filter(0.2, at: dt)
        filter.reset()
        XCTAssertEqual(filter.filter(0.9, at: 5), 0.9, "post-reset sample passes through")
    }

    func testPointWrapperFiltersAxesIndependently() {
        var pointFilter = PointOneEuroFilter(minCutoff: 1, beta: 0.5, dCutoff: 1)
        var xFilter = OneEuroFilter(minCutoff: 1, beta: 0.5, dCutoff: 1)
        var yFilter = OneEuroFilter(minCutoff: 1, beta: 0.5, dCutoff: 1)

        let path: [(Double, Double, TimeInterval)] = [
            (0.50, 0.50, 0),
            (0.52, 0.49, 1.0 / 60),
            (0.55, 0.47, 2.0 / 60),
            (0.60, 0.44, 3.0 / 60),
        ]
        for (x, y, t) in path {
            let filtered = pointFilter.filter(CGPoint(x: x, y: y), at: t)
            XCTAssertEqual(filtered.x, xFilter.filter(x, at: t), accuracy: 1e-12)
            XCTAssertEqual(filtered.y, yFilter.filter(y, at: t), accuracy: 1e-12)
        }
    }

    // MARK: - Helpers

    private func standardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}

/// Deterministic pseudo-random numbers (SplitMix64) for repeatable jitter.
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

    mutating func unitDouble() -> Double {
        Double(next() >> 11) * (1.0 / Double(1 << 53))
    }

    mutating func jitter(_ magnitude: Double) -> Double {
        (unitDouble() * 2 - 1) * magnitude
    }
}
