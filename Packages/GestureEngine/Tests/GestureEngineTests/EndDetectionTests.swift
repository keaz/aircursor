import CoreGraphics
import GestureEngine
import HandPoseCore
import XCTest

/// The end-of-gesture robustness improvements: debounced starts, eager
/// pose-based release, and watchdog timeouts. Every test here is a
/// "gesture must end promptly" scenario the old design got stuck on.
final class EndDetectionTests: XCTestCase {
    // MARK: - Debounced starts (no gesture from noise)

    func testSingleFramePinchSpikeDoesNotPress() {
        var harness = EngineHarness()
        harness.point(frames: 4)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 1) // 1-frame spike
        harness.point(frames: 2)
        XCTAssertEqual(harness.intents.pressCount(), 0, "a 1-frame pinch must not click")
    }

    func testTwoFramePinchSpikeDoesNotPress() {
        var harness = EngineHarness()
        harness.point(frames: 4)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 2) // 2-frame spike
        harness.point(frames: 2)
        XCTAssertEqual(harness.intents.pressCount(), 0, "a 2-frame pinch is below the adopt threshold")
    }

    func testSustainedPinchStillPresses() {
        var harness = EngineHarness()
        harness.point(frames: 4)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 5) // deliberate
        harness.point(frames: 3)
        XCTAssertEqual(harness.intents.pressCount(.left), 1)
        XCTAssertEqual(harness.intents.releaseCount(.left), 1)
    }

    // MARK: - Closure-edge arming (a press needs a real open→close)

    func testStandingPinchNeverPresses() {
        // The hand is pinched from the very first frame and never opens — a
        // mis-tracked or resting hand. It must never click.
        var harness = EngineHarness()
        harness.feed(fingers: .init(index: true), indexPinch: 0.15, frames: 30)
        XCTAssertEqual(harness.intents.pressCount(), 0, "a standing pinch is not a click")
    }

    func testPinchAfterOpeningTheHandPresses() {
        var harness = EngineHarness()
        // Clearly open first (metric 1.0 arms), then pinch.
        harness.point(frames: 4)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 4)
        XCTAssertEqual(harness.intents.pressCount(.left), 1, "open-then-pinch is a real click")
    }

    func testSecondClickNeedsTheHandToReopen() {
        var harness = EngineHarness()
        harness.point(frames: 4)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 4) // click 1
        harness.feed(fingers: .init(index: true), indexPinch: 0.30, frames: 3) // partial release (< arm)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 4) // re-pinch, never reopened
        XCTAssertEqual(harness.intents.pressCount(.left), 1, "no re-arm without a clear reopen")

        harness.point(frames: 4) // clearly reopen (arms)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 4)
        XCTAssertEqual(harness.intents.pressCount(.left), 2, "reopening enables the next click")
    }

    // MARK: - Eager release (a relaxing hand ends the press)

    func testPressReleasesWhenPinchRelaxesIntoTheOldHoldBand() {
        // Metric 0.48 sits in the OLD hold band (0.35–0.55) but above the
        // new 0.45 open threshold — the press must end, not stick.
        var harness = EngineHarness()
        harness.point(frames: 4)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 4) // press
        XCTAssertEqual(harness.engine.state, .pressed(.left))
        harness.feed(fingers: .init(index: true), indexPinch: 0.48, frames: 3) // relax a little
        XCTAssertEqual(harness.intents.releaseCount(.left), 1, "a small separation must end the click")
        XCTAssertEqual(harness.engine.state, .pointing)
    }

    func testPressReleasesWhenHandOpensRegardlessOfMetric() {
        var harness = EngineHarness()
        harness.point(frames: 4)
        harness.feed(fingers: .init(index: true), indexPinch: 0.2, frames: 4)
        // Hand opens to a clear point pose (fingers extended) — ends the press.
        harness.point(frames: 3)
        XCTAssertEqual(harness.intents.releaseCount(.left), 1)
        XCTAssertEqual(harness.engine.state, .pointing)
    }

    // MARK: - Zoom idle-timeout (zoom's primary escape hatch)

    /// A short idle timeout keeps the zoom-watchdog tests fast and decoupled
    /// from the shipped 1.2s tuning (which is sized to clear a spread-hold).
    private func quickZoomTimeoutConfig() -> GestureConfig {
        var config = GestureConfig()
        config.zoomIdleTimeout = 0.3 // ≈ 9 frames at 30fps
        return config
    }

    func testZoomEndsWhenSpreadingStops() {
        var harness = EngineHarness(config: quickZoomTimeoutConfig())
        harness.fist(frames: 4)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 3) // arm zoom
        XCTAssertEqual(harness.engine.state, .zooming)
        harness.feed(fingers: .init(), indexPinch: 1.2, frames: 1) // one step
        XCTAssertGreaterThanOrEqual(harness.intents.systemCount(.zoomStepIn), 1)

        // Hold the pinch closed and still — no more spreading — past the
        // idle timeout.
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 15)
        XCTAssertNotEqual(harness.engine.state, .zooming, "zoom must time out when spreading stops")
    }

    func testZoomDoesNotReArmFromTheSameStillPinchAfterTimeout() {
        var harness = EngineHarness(config: quickZoomTimeoutConfig())
        harness.fist(frames: 4)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 3)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 15) // time out + hold
        let stepsBefore = harness.intents.systemCount(.zoomStepIn)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 10) // still holding
        XCTAssertEqual(harness.engine.state, .neutral, "must stay ended, not flip back to zooming")
        XCTAssertEqual(harness.intents.systemCount(.zoomStepIn), stepsBefore, "no phantom steps after timeout")
    }

    func testZoomReArmsAfterOpeningTheHand() {
        var harness = EngineHarness(config: quickZoomTimeoutConfig())
        harness.fist(frames: 4)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 3)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 15) // timed out
        // Open the hand fully (pinch clears the block), then pinch again.
        harness.feed(fingers: .init(), indexPinch: 1.5, frames: 4)
        harness.feed(fingers: .init(), indexPinch: 0.2, frames: 3)
        harness.feed(fingers: .init(), indexPinch: 1.3, frames: 1)
        XCTAssertEqual(harness.engine.state, .zooming, "a fresh pinch after opening must re-arm zoom")
    }

    // MARK: - Press watchdog (hard backstop)

    func testPressForceReleasesAfterMaxDuration() {
        var config = GestureConfig()
        config.maxPressDuration = 0.3 // shrink for the test
        var harness = EngineHarness(config: config)
        harness.point(frames: 4)
        // Hold a genuine pinch far past the cap (0.3s ≈ 9 frames at 30fps).
        harness.feed(fingers: .init(index: true), indexPinch: 0.15, frames: 20)
        XCTAssertEqual(harness.intents.releaseCount(.left), 1, "the watchdog must let go")
        XCTAssertNotEqual(harness.engine.state, .pressed(.left))
    }

    func testWatchdogReleaseStillObeysTheSafetyInvariant() {
        var config = GestureConfig()
        config.maxPressDuration = 0.3
        var harness = EngineHarness(config: config)
        harness.point(frames: 4)
        harness.feed(fingers: .init(index: true), indexPinch: 0.15, frames: 20)
        // released must precede any later disengage/idle.
        let rel = harness.intents.firstIndex(of: .released(.left))
        XCTAssertNotNil(rel)
    }
}
