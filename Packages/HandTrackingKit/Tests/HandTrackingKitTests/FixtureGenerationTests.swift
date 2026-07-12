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

    /// Pinch, then move far and long enough to promote to a drag, then the
    /// hand vanishes mid-drag. Expected in M3: dragEnded is emitted before
    /// the engine goes idle — a stuck drag must be impossible.
    private func handLossMidDrag() -> [HandPoseFrame] {
        var builder = FrameSequenceBuilder()
        appendRamp(&builder, from: openRatio, to: openRatio, frames: 10)
        appendRamp(&builder, from: openRatio, to: closedRatio, frames: 6)
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
