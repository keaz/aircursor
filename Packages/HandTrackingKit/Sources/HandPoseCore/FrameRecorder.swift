import Foundation

/// Collects landmark frames from a live stream and writes them as a fixture
/// JSON file to a user-chosen path.
///
/// Frame streams are single-consumer, so the recorder does not attach to the
/// stream itself: the pipeline's consuming loop feeds every frame through
/// `record(_:session:)` while a recording is active.
///
/// Every recording is a numbered *session*. `beginRecording()` returns a
/// fresh session token; `record`/`endRecording`/`cancelRecording` take it and
/// ignore any token that isn't current. This makes start/stop atomic across
/// the actor boundary — a frame or an end/cancel left over from a previous
/// (e.g. capped) recording can never leak into a new one, and the buffer is
/// cleared on begin, end, and cancel so a stale count is impossible.
///
/// Recording is bounded to `maxFrames` so an accidental long recording cannot
/// grow memory without limit.
///
/// Landmarks only — recording camera frames or any image data is forbidden.
public actor FrameRecorder {
    /// Outcome of feeding one frame.
    public struct RecordResult: Equatable, Sendable {
        /// Whether the frame belonged to the current session and was stored.
        public let accepted: Bool
        /// Frames accepted so far in the current session.
        public let frameCount: Int
        /// The recording reached its frame cap and stopped accepting frames.
        public let reachedLimit: Bool
    }

    private var frames: [HandPoseFrame] = []
    private var isRecording = false
    /// Monotonic session token. 0 means "no session has begun".
    private var currentSession = 0

    /// Upper bound on stored frames. Default ≈ 3 minutes at 30 fps.
    public let maxFrames: Int

    public init(maxFrames: Int = 5400) {
        precondition(maxFrames > 0, "maxFrames must be positive")
        self.maxFrames = maxFrames
    }

    /// Begins a new recording, clearing any prior buffer, and returns the
    /// session token to tag subsequent calls with.
    public func beginRecording() -> Int {
        frames.removeAll(keepingCapacity: true)
        isRecording = true
        currentSession += 1
        return currentSession
    }

    /// Records one frame if `session` is current, active, and under the cap.
    /// Returns whether it was accepted, the running count, and whether the
    /// cap has been reached (after which no further frames are stored).
    @discardableResult
    public func record(_ frame: HandPoseFrame, session: Int) -> RecordResult {
        // A frame from a superseded session tells the caller nothing about
        // the current one.
        guard session == currentSession else {
            return RecordResult(accepted: false, frameCount: 0, reachedLimit: false)
        }
        // Current session but already ended or capped: report its real state.
        guard isRecording else {
            return RecordResult(
                accepted: false, frameCount: frames.count, reachedLimit: frames.count >= maxFrames
            )
        }
        if frames.count < maxFrames {
            frames.append(frame)
        }
        let atLimit = frames.count >= maxFrames
        if atLimit {
            isRecording = false // stop accepting at the cap
        }
        return RecordResult(accepted: true, frameCount: frames.count, reachedLimit: atLimit)
    }

    /// Ends the given session and writes the collected landmarks as fixture
    /// JSON, then clears the buffer. A stale session is a no-op returning 0.
    @discardableResult
    public func endRecording(session: Int, writingTo url: URL) throws -> Int {
        guard session == currentSession else { return 0 }
        isRecording = false
        let fixture = HandPoseFixture(frames: frames)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(fixture)
        try data.write(to: url, options: .atomic)
        frames.removeAll(keepingCapacity: false)
        return fixture.frames.count
    }

    /// Cancels the given session and discards its frames. A stale session is
    /// a no-op.
    public func cancelRecording(session: Int) {
        guard session == currentSession else { return }
        isRecording = false
        frames.removeAll(keepingCapacity: false)
    }
}
