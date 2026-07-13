import GestureEngine
import HandPoseCore
import XCTest

final class ZoomTraceProbe: XCTestCase {
    func testTrace() throws {
        var engine = GestureEngine()
        var streak = 0
        var origin: CGPoint?
        for (i, frame) in try FixtureLoader.frames("recorded/zoom_in").enumerated() {
            _ = engine.consume(frame)
            guard let snap = engine.lastSnapshot, let w = frame.joints[.wrist] else { continue }
            switch snap.pose {
            case .pinched, .neutral:
                streak = 0; origin = nil
            default:
                streak += 1
                if origin == nil { origin = w }
            }
            if (55...70).contains(i) {
                let travel = origin.map { hypot(w.x - $0.x, w.y - $0.y) } ?? 0
                print("f\(i) pose=\(snap.pose) streak=\(streak) travel=\(String(format: "%.3f", travel)) state=\(engine.state)")
            }
        }
    }
}
