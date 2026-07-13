import Foundation

/// Collects landmark frames from a live stream and writes them as a fixture
/// JSON file to a user-chosen path.
///
/// Frame streams are single-consumer, so the recorder does not attach to the
/// stream itself: the pipeline's consuming loop feeds every frame through
/// `record(_:)` while a recording is active. `record(_:)` returns the running
/// count so the UI can mirror the recorder's state exactly — a frame that
/// arrives before `beginRecording()` is not counted, so the on-screen counter
/// can never claim more frames than are saved.
///
/// Recording is bounded to `maxFrames` so an accidental long recording cannot
/// grow memory without limit.
///
/// Landmarks only — recording camera frames or any image data is forbidden.
public actor FrameRecorder {
    /// Outcome of feeding one frame.
    public struct RecordResult: Equatable, Sendable {
        /// Frames accepted so far in this recording.
        public let frameCount: Int
        /// The recording reached its frame cap and stopped accepting frames.
        public let reachedLimit: Bool
    }

    private var frames: [HandPoseFrame] = []
    private var isRecording = false

    /// Upper bound on stored frames. Default ≈ 3 minutes at 30 fps.
    public let maxFrames: Int

    public init(maxFrames: Int = 5400) {
        precondition(maxFrames > 0, "maxFrames must be positive")
        self.maxFrames = maxFrames
    }

    public func beginRecording() {
        frames.removeAll()
        isRecording = true
    }

    /// Records one frame when active and under the cap. Returns the running
    /// count and whether the cap has been reached (after which no further
    /// frames are stored, bounding memory).
    @discardableResult
    public func record(_ frame: HandPoseFrame) -> RecordResult {
        if isRecording {
            if frames.count < maxFrames {
                frames.append(frame)
            }
            if frames.count >= maxFrames {
                isRecording = false // stop accepting at the cap
            }
        }
        return RecordResult(frameCount: frames.count, reachedLimit: frames.count >= maxFrames)
    }

    /// Stops recording and writes the collected landmarks as fixture JSON.
    /// Returns the number of frames written.
    @discardableResult
    public func endRecording(writingTo url: URL) throws -> Int {
        isRecording = false
        let fixture = HandPoseFixture(frames: frames)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(fixture)
        try data.write(to: url, options: .atomic)
        return fixture.frames.count
    }

    public func cancelRecording() {
        isRecording = false
        frames.removeAll()
    }
}
