/// A producer of hand-pose frames. Implementations: the live camera source in
/// `HandTrackingKit` and `ReplaySource` for fixtures.
///
/// Streams use newest-only buffering: a slow consumer must never see a stale
/// hand position.
public protocol HandPoseSource: Sendable {
    var frames: AsyncStream<HandPoseFrame> { get }
    func start() async throws
    func stop()
}
