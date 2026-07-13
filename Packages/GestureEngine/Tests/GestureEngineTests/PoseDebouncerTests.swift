import GestureEngine
import XCTest

/// The debouncer is asymmetric: active poses (pinched, scroll) that START a
/// gesture must persist `adoptFrames`, while calm poses (point, neutral,
/// openPalm) that END one take hold in `releaseFrames`. Slow to grab, fast
/// to let go.
final class PoseDebouncerTests: XCTestCase {
    private func feed(_ d: inout PoseDebouncer, _ poses: [HandPose], adopt: Int = 3, release: Int = 2) -> [HandPose] {
        poses.map { d.update($0, adoptFrames: adopt, releaseFrames: release) }
    }

    func testActivePoseNeedsAdoptFramesToTakeHold() {
        var d = PoseDebouncer(initial: .point)
        // Two frames of pinch is not enough (adopt = 3).
        XCTAssertEqual(feed(&d, [.pinched, .pinched]), [.point, .point])
        // The third consecutive frame commits it.
        XCTAssertEqual(d.update(.pinched, adoptFrames: 3, releaseFrames: 2), .pinched)
    }

    func testSingleFrameActiveSpikeIsRejected() {
        var d = PoseDebouncer(initial: .point)
        XCTAssertEqual(feed(&d, [.pinched, .point, .pinched, .point]), [.point, .point, .point, .point])
    }

    func testCalmPoseEndsGestureInReleaseFrames() {
        var d = PoseDebouncer(initial: .pinched)
        // Releasing a pinch: two frames of point commit the release (< adopt).
        XCTAssertEqual(feed(&d, [.point, .point]), [.pinched, .point])
    }

    func testSingleCalmSpikeDoesNotEndAnActiveGesture() {
        var d = PoseDebouncer(initial: .pinched)
        // One stray point frame mid-pinch must not drop the gesture.
        XCTAssertEqual(feed(&d, [.point, .pinched]), [.pinched, .pinched])
    }

    func testReleaseIsNoSlowerThanAdopt() {
        // The whole point: ending is at least as responsive as starting.
        var starting = PoseDebouncer(initial: .point)
        var startFrames = 0
        while starting.update(.pinched, adoptFrames: 3, releaseFrames: 2) != .pinched { startFrames += 1 }

        var ending = PoseDebouncer(initial: .pinched)
        var endFrames = 0
        while ending.update(.point, adoptFrames: 3, releaseFrames: 2) != .point { endFrames += 1 }

        XCTAssertLessThanOrEqual(endFrames, startFrames)
    }

    func testChangingCandidateResetsTheCount() {
        var d = PoseDebouncer(initial: .neutral)
        // Alternating active candidates never accumulate enough to commit.
        XCTAssertEqual(feed(&d, [.pinched, .scroll, .pinched, .scroll]), [.neutral, .neutral, .neutral, .neutral])
    }

    func testResetForcesPoseImmediately() {
        var d = PoseDebouncer(initial: .pinched)
        d.reset(to: .neutral)
        XCTAssertEqual(d.pose, .neutral)
    }
}
