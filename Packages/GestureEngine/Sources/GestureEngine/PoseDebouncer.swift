/// Debounces the classified pose before the state machine reacts, so a
/// one- or two-frame noise spike can neither start nor end a gesture.
///
/// Asymmetric by design: an *active* pose (pinched, scroll) — one that
/// starts a press/scroll/zoom — must persist `adoptFrames` before it takes
/// hold, but a *calm* pose (point, neutral, openPalm) — the poses that end
/// gestures — takes hold in `releaseFrames`. Slow to grab, fast to let go,
/// so a gesture never gets stuck waiting for a clean opposite reading.
public struct PoseDebouncer: Sendable {
    public private(set) var pose: HandPose
    private var candidate: HandPose?
    private var candidateCount = 0

    public init(initial: HandPose = .neutral) {
        self.pose = initial
    }

    /// Feeds one raw classified pose and returns the debounced pose.
    public mutating func update(_ raw: HandPose, adoptFrames: Int, releaseFrames: Int) -> HandPose {
        if raw == pose {
            candidate = nil
            candidateCount = 0
            return pose
        }
        if raw == candidate {
            candidateCount += 1
        } else {
            candidate = raw
            candidateCount = 1
        }
        let needed = max(1, Self.isCalm(raw) ? releaseFrames : adoptFrames)
        if candidateCount >= needed {
            pose = raw
            candidate = nil
            candidateCount = 0
        }
        return pose
    }

    public mutating func reset(to pose: HandPose = .neutral) {
        self.pose = pose
        candidate = nil
        candidateCount = 0
    }

    /// Calm poses freeze or end gestures; active poses start them.
    static func isCalm(_ pose: HandPose) -> Bool {
        switch pose {
        case .point, .neutral, .openPalm: return true
        case .pinched, .scroll: return false
        }
    }
}
