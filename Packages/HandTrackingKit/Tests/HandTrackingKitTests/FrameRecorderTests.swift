import CoreGraphics
import Foundation
import HandPoseCore
import XCTest

final class FrameRecorderTests: XCTestCase {
    private let frames = [
        HandPoseFrame(joints: [.wrist: CGPoint(x: 0.5, y: 0.8)], timestamp: 0),
        HandPoseFrame(joints: [.wrist: CGPoint(x: 0.52, y: 0.79)], timestamp: 1.0 / 60),
        HandPoseFrame(joints: [:], timestamp: 2.0 / 60),
    ]

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aircursor-recorder-\(UUID().uuidString).json")
    }

    func testRecordAndWriteRoundTrip() async throws {
        let recorder = FrameRecorder()
        let session = await recorder.beginRecording()
        for frame in frames {
            await recorder.record(frame, session: session)
        }

        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try await recorder.endRecording(session: session, writingTo: url)

        XCTAssertEqual(written, frames.count)
        let fixture = try JSONDecoder().decode(HandPoseFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.frames, frames)
        XCTAssertEqual(fixture.version, HandPoseFixture.currentVersion)
    }

    func testCancelDiscardsFrames() async throws {
        let recorder = FrameRecorder()
        let session = await recorder.beginRecording()
        await recorder.record(frames[0], session: session)
        await recorder.cancelRecording(session: session)

        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try await recorder.endRecording(session: session, writingTo: url)
        XCTAssertEqual(written, 0)
    }

    func testRecordReturnsRunningCountSoTheUICanMatchExactly() async throws {
        let recorder = FrameRecorder()
        let session = await recorder.beginRecording()
        let first = await recorder.record(frames[0], session: session)
        XCTAssertEqual(first.frameCount, 1)
        XCTAssertTrue(first.accepted)
        let second = await recorder.record(frames[1], session: session)
        XCTAssertEqual(second.frameCount, 2)
    }

    func testFrameCapBoundsMemoryAndReportsTheLimit() async throws {
        let recorder = FrameRecorder(maxFrames: 3)
        let session = await recorder.beginRecording()

        var results: [FrameRecorder.RecordResult] = []
        for _ in 0..<10 {
            results.append(await recorder.record(frames[0], session: session))
        }

        XCTAssertEqual(results[2].frameCount, 3)
        XCTAssertTrue(results[2].reachedLimit, "the cap is reported when hit")
        XCTAssertEqual(results.last?.frameCount, 3, "memory is bounded at the cap")

        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try await recorder.endRecording(session: session, writingTo: url)
        XCTAssertEqual(written, 3)
    }

    // MARK: - Session isolation (issue #3 re-open scenarios)

    /// The reopened bug: a capped-then-restarted recording must not see the
    /// previous session's buffer or its reachedLimit.
    func testNewSessionAfterCapStartsCleanNoStaleBufferOrLimit() async throws {
        let recorder = FrameRecorder(maxFrames: 3)
        let s1 = await recorder.beginRecording()
        for _ in 0..<5 { await recorder.record(frames[0], session: s1) } // caps at 3

        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await recorder.endRecording(session: s1, writingTo: url) // writes, then clears

        let s2 = await recorder.beginRecording()
        XCTAssertNotEqual(s2, s1, "each recording gets a fresh session")
        let fresh = await recorder.record(frames[0], session: s2)
        XCTAssertEqual(fresh.frameCount, 1, "must not see the previous 3-frame buffer")
        XCTAssertFalse(fresh.reachedLimit, "must not inherit the previous cap")
        XCTAssertTrue(fresh.accepted)
    }

    func testStaleSessionRecordIsRejected() async throws {
        let recorder = FrameRecorder()
        let s1 = await recorder.beginRecording()
        let s2 = await recorder.beginRecording() // supersedes s1

        let stale = await recorder.record(frames[0], session: s1)
        XCTAssertFalse(stale.accepted, "a frame tagged with the old session is rejected")

        let current = await recorder.record(frames[0], session: s2)
        XCTAssertTrue(current.accepted)
        XCTAssertEqual(current.frameCount, 1)
    }

    func testEndAndCancelIgnoreStaleSessions() async throws {
        let recorder = FrameRecorder()
        let s1 = await recorder.beginRecording()
        await recorder.record(frames[0], session: s1)
        let s2 = await recorder.beginRecording() // s1 is now stale

        // A stale end/cancel must not touch the current session.
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let staleWrite = try await recorder.endRecording(session: s1, writingTo: url)
        XCTAssertEqual(staleWrite, 0, "stale end is a no-op")
        await recorder.cancelRecording(session: s1)

        let current = await recorder.record(frames[1], session: s2)
        XCTAssertTrue(current.accepted, "the current session is unaffected by stale calls")
    }
}
