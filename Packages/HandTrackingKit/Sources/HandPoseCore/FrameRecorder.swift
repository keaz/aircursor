import Foundation

/// Collects landmark frames from a live stream and writes them as a fixture
/// JSON file to a user-chosen path.
///
/// Frame streams are single-consumer, so the recorder does not attach to the
/// stream itself: the pipeline's consuming loop feeds every frame through
/// `record(_:)` while a recording is active.
///
/// Landmarks only — recording camera frames or any image data is forbidden.
public actor FrameRecorder {
    private var frames: [HandPoseFrame] = []
    private var isRecording = false

    public init() {}

    public func beginRecording() {
        frames.removeAll()
        isRecording = true
    }

    /// Ignored unless a recording is active.
    public func record(_ frame: HandPoseFrame) {
        guard isRecording else { return }
        frames.append(frame)
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
