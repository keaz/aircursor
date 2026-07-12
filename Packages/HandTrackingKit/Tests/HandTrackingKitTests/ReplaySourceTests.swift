import CoreGraphics
import Foundation
@testable import HandPoseCore
import XCTest

final class ReplaySourceTests: XCTestCase {
    private func makeFrames(count: Int, dt: TimeInterval = 1.0 / 60) -> [HandPoseFrame] {
        (0..<count).map { index in
            HandPoseFrame(
                joints: [.wrist: CGPoint(x: Double(index) / Double(max(count, 1)), y: 0.5)],
                timestamp: Double(index) * dt
            )
        }
    }

    private func tempFixtureURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aircursor-\(UUID().uuidString).json")
    }

    func testDeliversAllFramesInOrder() async throws {
        let frames = makeFrames(count: 20)
        // Unbounded buffer isolates ordering/completeness from drop policy.
        let source = ReplaySource(frames: frames, speed: 1000, bufferingPolicy: .unbounded)
        try await source.start()

        var received: [HandPoseFrame] = []
        for await frame in source.frames {
            received.append(frame)
        }
        XCTAssertEqual(received, frames)
    }

    func testNewestOnlyBufferingKeepsOnlyLatestFrame() async throws {
        let frames = makeFrames(count: 10)
        let source = ReplaySource(frames: frames, speed: 1_000_000)
        try await source.start()
        // Let playback finish before anyone consumes: with .bufferingNewest(1)
        // only the newest frame may survive.
        try await Task.sleep(for: .milliseconds(300))

        var received: [HandPoseFrame] = []
        for await frame in source.frames {
            received.append(frame)
        }
        XCTAssertEqual(received, [try XCTUnwrap(frames.last)])
    }

    func testSpeedMultiplierAcceleratesPlayback() async throws {
        // 2 s of fixture time at speed 100 should replay in well under 1 s.
        let frames = makeFrames(count: 21, dt: 0.1)
        let source = ReplaySource(frames: frames, speed: 100, bufferingPolicy: .unbounded)

        let clock = ContinuousClock()
        let start = clock.now
        try await source.start()
        var received = 0
        for await _ in source.frames {
            received += 1
        }
        let elapsed = clock.now - start

        XCTAssertEqual(received, frames.count)
        XCTAssertLessThan(elapsed, .seconds(1))
    }

    func testStopEndsStream() async throws {
        // 10 s gaps: playback is guaranteed to be sleeping when stop() lands.
        let frames = makeFrames(count: 3, dt: 10)
        let source = ReplaySource(frames: frames, speed: 1)
        try await source.start()

        var received = 0
        for await _ in source.frames {
            received += 1
            source.stop()
        }
        XCTAssertEqual(received, 1)
    }

    func testLoadsFixtureFromDisk() async throws {
        let frames = makeFrames(count: 5)
        let url = tempFixtureURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = FrameRecorder()
        await recorder.beginRecording()
        for frame in frames {
            await recorder.record(frame)
        }
        try await recorder.endRecording(writingTo: url)

        let source = try ReplaySource(contentsOf: url, speed: 1000)
        try await source.start()
        var received: [HandPoseFrame] = []
        for await frame in source.frames {
            received.append(frame)
        }
        // Newest-only buffering may legally drop, but a fast consumer of a
        // 5-frame fixture should see a non-empty ordered subsequence ending
        // at the final frame.
        XCTAssertEqual(received.last, frames.last)
        XCTAssertFalse(received.isEmpty)
    }

    func testRejectsUnsupportedFixtureVersion() throws {
        let url = tempFixtureURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let json = #"{"version":999,"frames":[]}"#
        try Data(json.utf8).write(to: url)

        XCTAssertThrowsError(try ReplaySource(contentsOf: url)) { error in
            XCTAssertEqual(error as? ReplayError, .unsupportedFixtureVersion(999))
        }
    }
}
