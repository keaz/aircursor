import CoreGraphics
import Foundation

/// One observation of a single hand.
public struct HandPoseFrame: Equatable, Sendable {
    /// Normalized [0,1], top-left origin, mirrored horizontally
    /// (moving the hand right increases x). Low-confidence joints absent.
    /// An empty dictionary means no hand was detected in this frame.
    public let joints: [HandJoint: CGPoint]

    /// Camera clock, seconds; filters use real dt between frames.
    public let timestamp: TimeInterval

    public init(joints: [HandJoint: CGPoint], timestamp: TimeInterval) {
        self.joints = joints
        self.timestamp = timestamp
    }
}

extension HandPoseFrame: Codable {
    /// Fixture JSON shape: `{"timestamp": 0.016, "joints": {"wrist": [0.5, 0.8], ...}}`.
    /// Points are `[x, y]` pairs keyed by `HandJoint` raw values.
    private enum CodingKeys: String, CodingKey {
        case joints
        case timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawJoints = try container.decode([String: [Double]].self, forKey: .joints)

        var joints: [HandJoint: CGPoint] = [:]
        joints.reserveCapacity(rawJoints.count)
        for (name, pair) in rawJoints {
            guard let joint = HandJoint(rawValue: name) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .joints, in: container,
                    debugDescription: "Unknown hand joint \"\(name)\""
                )
            }
            guard pair.count == 2 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .joints, in: container,
                    debugDescription: "Joint \"\(name)\" must be an [x, y] pair"
                )
            }
            joints[joint] = CGPoint(x: pair[0], y: pair[1])
        }

        self.joints = joints
        self.timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let rawJoints = joints.reduce(into: [String: [Double]]()) { result, entry in
            result[entry.key.rawValue] = [entry.value.x, entry.value.y]
        }
        try container.encode(rawJoints, forKey: .joints)
        try container.encode(timestamp, forKey: .timestamp)
    }
}
