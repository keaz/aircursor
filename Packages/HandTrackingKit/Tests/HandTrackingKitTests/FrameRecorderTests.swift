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
        await recorder.beginRecording()
        for frame in frames {
            await recorder.record(frame)
        }

        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try await recorder.endRecording(writingTo: url)

        XCTAssertEqual(written, frames.count)
        let fixture = try JSONDecoder().decode(HandPoseFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.frames, frames)
        XCTAssertEqual(fixture.version, HandPoseFixture.currentVersion)
    }

    func testFramesIgnoredWhileNotRecording() async throws {
        let recorder = FrameRecorder()
        await recorder.record(frames[0])
        await recorder.beginRecording()
        await recorder.record(frames[1])

        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try await recorder.endRecording(writingTo: url)

        XCTAssertEqual(written, 1)
        let fixture = try JSONDecoder().decode(HandPoseFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.frames, [frames[1]])
    }

    func testCancelDiscardsFrames() async throws {
        let recorder = FrameRecorder()
        await recorder.beginRecording()
        await recorder.record(frames[0])
        await recorder.cancelRecording()

        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try await recorder.endRecording(writingTo: url)
        XCTAssertEqual(written, 0)
    }
}
