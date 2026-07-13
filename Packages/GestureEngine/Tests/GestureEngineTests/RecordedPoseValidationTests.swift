import GestureEngine
import HandPoseCore
import XCTest

/// Validates the pose classifier against the user's real recorded gestures
/// (`Fixtures/recorded/`). Bounds are diagnostic, not exact: they encode
/// what each recording must predominantly look like for the engine built on
/// top to behave. If these fail, thresholds — not the recordings — are wrong.
final class RecordedPoseValidationTests: XCTestCase {
    private struct PoseCensus {
        var counts: [HandPose: Int] = [:]
        var classified = 0
        var extendedCounts: [Int] = []

        func fraction(_ pose: HandPose) -> Double {
            classified == 0 ? 0 : Double(counts[pose, default: 0]) / Double(classified)
        }

        /// Bloom cycles: extended-finger count rising from ≤1 to 4 within
        /// `window` frames — how the Mission Control detector will trigger.
        func blooms(window: Int = 4) -> Int {
            var blooms = 0
            var fistIndex: Int?
            for (index, count) in extendedCounts.enumerated() {
                if count <= 1 {
                    fistIndex = index
                } else if count == 4, let start = fistIndex {
                    if index - start <= window {
                        blooms += 1
                    }
                    fistIndex = nil
                }
            }
            return blooms
        }
    }

    private func census(_ fixture: String) throws -> PoseCensus {
        var classifier = PoseClassifier()
        var census = PoseCensus()
        for frame in try FixtureLoader.frames(fixture) {
            guard let snapshot = classifier.classify(frame) else { continue }
            census.classified += 1
            census.counts[snapshot.pose, default: 0] += 1
            census.extendedCounts.append(snapshot.fingers.extendedCount)
        }
        XCTAssertGreaterThan(census.classified, 50, "\(fixture): too few classified frames")
        return census
    }

    func testMouseMoveIsPredominantlyPointing() throws {
        let census = try census("recorded/mouse_move")
        XCTAssertGreaterThan(census.fraction(.point), 0.85)
        XCTAssertEqual(census.fraction(.pinched), 0, "pointing must never read as pinched")
    }

    func testScrollRecordingsShowTheScrollPose() throws {
        // scroll_down's style spends longer in curled returns than
        // scroll_up's (measured 0.16 vs 0.4 scroll-pose fraction); strokes
        // are what matter, so the floor is a presence bound.
        for fixture in ["recorded/scroll_up", "recorded/scroll_down"] {
            let census = try census(fixture)
            XCTAssertGreaterThan(census.fraction(.scroll), 0.12, fixture)
            XCTAssertLessThan(census.fraction(.openPalm), 0.1, fixture)
        }
    }

    func testZoomRecordingIsPinchDominant() throws {
        let census = try census("recorded/zoom_in")
        XCTAssertGreaterThan(census.fraction(.pinched), 0.4)
    }

    func testSwipeRecordingsAreOpenPalmDominant() throws {
        for fixture in ["recorded/swipe_left", "recorded/swipe_right"] {
            let census = try census(fixture)
            XCTAssertGreaterThan(census.fraction(.openPalm), 0.45, fixture)
        }
    }

    func testMissionControlAlternatesFistAndPalm() throws {
        // The fist phases are blink-brief (the bloom completes within a
        // frame), so dwell fraction is tiny — what the bloom detector needs
        // is the neutral→openPalm TRANSITIONS.
        let census = try census("recorded/mission_control")
        XCTAssertGreaterThan(census.fraction(.openPalm), 0.25)
        XCTAssertGreaterThan(census.fraction(.neutral), 0.01, "the fist phases must be visible")
        XCTAssertGreaterThanOrEqual(
            census.blooms(), 2,
            "bloom cycles (≤1 → 4 extended fingers within 4 frames) must be detectable"
        )
    }
}
