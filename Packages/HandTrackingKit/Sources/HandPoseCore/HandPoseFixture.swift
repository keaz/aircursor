import Foundation

/// The on-disk landmark fixture format. Landmark data only — recording camera
/// frames or any image data is forbidden.
public struct HandPoseFixture: Equatable, Sendable, Codable {
    public static let currentVersion = 1

    public let version: Int
    public let frames: [HandPoseFrame]

    public init(frames: [HandPoseFrame]) {
        self.version = Self.currentVersion
        self.frames = frames
    }
}
