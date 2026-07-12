import Foundation

public enum ReplayError: Error, Equatable, Sendable {
    case unsupportedFixtureVersion(Int)
}

/// Plays back a landmark fixture as a live-like frame stream, preserving the
/// original inter-frame timing (divided by `speed`). Used by tests and for
/// camera-free development.
///
/// A source instance is single-use: the stream finishes when playback reaches
/// the end or `stop()` is called. Create a new instance to replay again.
public final class ReplaySource: HandPoseSource, @unchecked Sendable {
    private let stream: AsyncStream<HandPoseFrame>
    private let continuation: AsyncStream<HandPoseFrame>.Continuation
    private let fixtureFrames: [HandPoseFrame]
    private let speed: Double

    // Guards `playback`/`started`; everything else is immutable.
    private let lock = NSLock()
    private var playback: Task<Void, Never>?
    private var started = false

    public var frames: AsyncStream<HandPoseFrame> { stream }

    public convenience init(frames: [HandPoseFrame], speed: Double = 1) {
        self.init(frames: frames, speed: speed, bufferingPolicy: .bufferingNewest(1))
    }

    /// Tests override the newest-only policy to assert lossless delivery;
    /// the pipeline always uses newest-only so stale positions are dropped.
    init(
        frames: [HandPoseFrame],
        speed: Double,
        bufferingPolicy: AsyncStream<HandPoseFrame>.Continuation.BufferingPolicy
    ) {
        precondition(speed > 0, "speed must be positive")
        self.fixtureFrames = frames
        self.speed = speed
        (self.stream, self.continuation) = AsyncStream.makeStream(
            of: HandPoseFrame.self, bufferingPolicy: bufferingPolicy
        )
    }

    /// Loads a fixture JSON file written by `FrameRecorder` (or authored
    /// synthetically).
    public convenience init(contentsOf url: URL, speed: Double = 1) throws {
        let data = try Data(contentsOf: url)
        let fixture = try JSONDecoder().decode(HandPoseFixture.self, from: data)
        guard fixture.version == HandPoseFixture.currentVersion else {
            throw ReplayError.unsupportedFixtureVersion(fixture.version)
        }
        self.init(frames: fixture.frames, speed: speed)
    }

    public func start() async throws {
        startPlayback()
    }

    public func stop() {
        let task = lock.withLock {
            let task = playback
            playback = nil
            return task
        }
        task?.cancel()
        continuation.finish()
    }

    private func startPlayback() {
        lock.withLock {
            guard !started else { return }
            started = true
            playback = Task { [fixtureFrames, speed, continuation] in
                var previousTimestamp: TimeInterval?
                for frame in fixtureFrames {
                    if let previous = previousTimestamp {
                        let delay = (frame.timestamp - previous) / speed
                        if delay > 0 {
                            try? await Task.sleep(for: .seconds(delay))
                        }
                    }
                    if Task.isCancelled { break }
                    continuation.yield(frame)
                    previousTimestamp = frame.timestamp
                }
                continuation.finish()
            }
        }
    }
}
