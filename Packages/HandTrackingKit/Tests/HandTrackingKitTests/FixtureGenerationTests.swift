import CoreGraphics
import Foundation
import HandPoseCore
import XCTest

/// Regenerates the committed synthetic fixtures in `Fixtures/`. Skipped in
/// normal runs; execute explicitly with:
///
///     REGENERATE_FIXTURES=1 swift test --package-path Packages/HandTrackingKit \
///         --filter FixtureGenerationTests
///
/// The fixtures are engine-agnostic landmark sequences; GestureEngine tests
/// (M3) assert on the intent sequences they produce.
final class FixtureGenerationTests: XCTestCase {
    private let openRatio = 1.0
    private let closedRatio = 0.15

    func testRegenerateFixtures() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["REGENERATE_FIXTURES"] == "1",
            "Set REGENERATE_FIXTURES=1 to rewrite the committed fixtures"
        )

        let directory = FixtureLocations.fixturesDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try write(smoothPinchTap(), to: directory.appendingPathComponent("smooth_pinch_tap.json"))
        try write(jitteryPinchHold(), to: directory.appendingPathComponent("jittery_pinch_hold.json"))
        try write(handLossMidDrag(), to: directory.appendingPathComponent("hand_loss_mid_drag.json"))
        try write(middlePinchScroll(), to: directory.appendingPathComponent("middle_pinch_scroll.json"))
    }

    /// Thumb–middle pinch, held still past tapDuration to promote to
    /// scrolling, then half a second of upward hand movement, then release.
    /// Expected in M4: scrollBy intents (dy < 0) ending with scrollEnded —
    /// and never a clutch engage or click.
    private func middlePinchScroll() -> [HandPoseFrame] {
        var builder = FrameSequenceBuilder()
        for _ in 0..<10 {
            builder.append(joints: SyntheticHand.joints(thumbIndexRatio: openRatio, thumbMiddleRatio: 1.1))
        }
        for i in 0..<5 {
            let ratio = 1.1 + (closedRatio - 1.1) * Double(i) / 4
            builder.append(joints: SyntheticHand.joints(thumbIndexRatio: openRatio, thumbMiddleRatio: ratio))
        }
        // Still hold past tapDuration promotes the pinch to scrolling.
        for _ in 0..<16 {
            builder.append(joints: SyntheticHand.joints(thumbIndexRatio: openRatio, thumbMiddleRatio: closedRatio))
        }
        for i in 0..<30 {
            let center = CGPoint(x: 0.5, y: 0.55 - Double(i) * 0.004)
            builder.append(joints: SyntheticHand.joints(center: center, thumbIndexRatio: openRatio, thumbMiddleRatio: closedRatio))
        }
        let releasedCenter = CGPoint(x: 0.5, y: 0.55 - 29 * 0.004)
        for i in 0..<5 {
            let ratio = closedRatio + (1.1 - closedRatio) * Double(i) / 4
            builder.append(joints: SyntheticHand.joints(center: releasedCenter, thumbIndexRatio: openRatio, thumbMiddleRatio: ratio))
        }
        for _ in 0..<10 {
            builder.append(joints: SyntheticHand.joints(center: releasedCenter, thumbIndexRatio: openRatio, thumbMiddleRatio: 1.1))
        }
        return builder.frames
    }

    /// Open hand → quick thumb–index pinch (~130 ms, stationary) → open.
    /// Expected intents in M3: [engaged, click(.left), disengaged].
    private func smoothPinchTap() -> [HandPoseFrame] {
        var builder = FrameSequenceBuilder()
        appendRamp(&builder, from: openRatio, to: openRatio, frames: 12)
        appendRamp(&builder, from: openRatio, to: closedRatio, frames: 6)
        appendRamp(&builder, from: closedRatio, to: closedRatio, frames: 8)
        appendRamp(&builder, from: closedRatio, to: openRatio, frames: 6)
        appendRamp(&builder, from: openRatio, to: openRatio, frames: 12)
        return builder.frames
    }

    /// Pinch engages, then one second of measurement noise: the pinch ratio
    /// wanders inside the hysteresis band (crossing the close threshold but
    /// never the open threshold) while the whole hand trembles ±0.002. The
    /// gate must not flicker and the resting cursor must not wander.
    private func jitteryPinchHold() -> [HandPoseFrame] {
        var generator = SeededGenerator(seed: 0xA1BC)
        var builder = FrameSequenceBuilder()
        appendRamp(&builder, from: openRatio, to: openRatio, frames: 10)
        appendRamp(&builder, from: openRatio, to: closedRatio, frames: 5)
        for _ in 0..<60 {
            let ratio = 0.32 + generator.unitDouble() * 0.16 // 0.32–0.48
            let center = CGPoint(
                x: 0.5 + generator.jitter(0.002),
                y: 0.55 + generator.jitter(0.002)
            )
            builder.append(joints: SyntheticHand.joints(center: center, thumbIndexRatio: ratio))
        }
        appendRamp(&builder, from: closedRatio, to: openRatio, frames: 10)
        return builder.frames
    }

    /// Pinch, hold still past tapDuration so the drag arms (button down),
    /// drag for half a second, then the hand vanishes mid-drag. Expected in
    /// M3: dragEnded is emitted before the engine goes idle — a stuck drag
    /// must be impossible.
    private func handLossMidDrag() -> [HandPoseFrame] {
        var builder = FrameSequenceBuilder()
        appendRamp(&builder, from: openRatio, to: openRatio, frames: 10)
        appendRamp(&builder, from: openRatio, to: closedRatio, frames: 6)
        // Still hold: 20 frames ≈ 333 ms, comfortably past the 250 ms
        // tapDuration, promoting the pinch to a drag.
        appendRamp(&builder, from: closedRatio, to: closedRatio, frames: 20)
        for i in 0..<30 {
            let center = CGPoint(x: 0.5 + Double(i) * 0.005, y: 0.55 - Double(i) * 0.003)
            builder.append(joints: SyntheticHand.joints(center: center, thumbIndexRatio: closedRatio))
        }
        for _ in 0..<15 {
            builder.appendHandLost()
        }
        return builder.frames
    }

    private func appendRamp(
        _ builder: inout FrameSequenceBuilder,
        from start: Double,
        to end: Double,
        frames count: Int
    ) {
        for i in 0..<count {
            let progress = count == 1 ? 1 : Double(i) / Double(count - 1)
            let ratio = start + (end - start) * progress
            builder.append(joints: SyntheticHand.joints(thumbIndexRatio: ratio))
        }
    }

    private func write(_ frames: [HandPoseFrame], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(HandPoseFixture(frames: frames))
        try data.write(to: url, options: .atomic)
    }
}
