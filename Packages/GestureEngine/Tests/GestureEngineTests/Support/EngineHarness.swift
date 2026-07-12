import CoreGraphics
import Foundation
import GestureEngine
import HandPoseCore

/// Minimal six-joint hand for engine tests. Geometry is chosen so the pinch
/// metrics equal the requested ratios *exactly*: the wrist–middleMCP span is
/// 0.2 and each tip sits at `ratio × 0.2` from the thumb tip along one axis.
/// All joints translate rigidly with `center`.
enum TestHand {
    static let span = 0.2

    static func joints(
        center: CGPoint = CGPoint(x: 0.5, y: 0.55),
        indexRatio: Double,
        middleRatio: Double = 1.1
    ) -> [HandJoint: CGPoint] {
        let wrist = CGPoint(x: center.x, y: center.y + 0.25)
        let middleMCP = CGPoint(x: wrist.x, y: wrist.y - span)
        let indexMCP = CGPoint(x: middleMCP.x - 0.045, y: middleMCP.y + 0.01)
        let thumbTip = CGPoint(x: center.x - 0.04, y: center.y)
        let indexTip = CGPoint(x: thumbTip.x + indexRatio * span, y: thumbTip.y)
        let middleTip = CGPoint(x: thumbTip.x, y: thumbTip.y - middleRatio * span)
        return [
            .wrist: wrist,
            .middleMCP: middleMCP,
            .indexMCP: indexMCP,
            .thumbTip: thumbTip,
            .indexTip: indexTip,
            .middleTip: middleTip,
        ]
    }
}

/// Feeds frames at 60 fps and accumulates the engine's emitted intents.
struct EngineHarness {
    var engine: GestureEngine
    private(set) var intents: [PointerIntent] = []
    private var timestamp: TimeInterval = 0
    let dt = 1.0 / 60

    init(config: GestureConfig = GestureConfig()) {
        self.engine = GestureEngine(config: config)
    }

    @discardableResult
    mutating func feed(
        indexRatio: Double,
        middleRatio: Double = 1.1,
        center: CGPoint = CGPoint(x: 0.5, y: 0.55),
        frames: Int = 1
    ) -> [PointerIntent] {
        var batch: [PointerIntent] = []
        for _ in 0..<frames {
            let frame = HandPoseFrame(
                joints: TestHand.joints(center: center, indexRatio: indexRatio, middleRatio: middleRatio),
                timestamp: timestamp
            )
            batch += engine.consume(frame)
            timestamp += dt
        }
        intents += batch
        return batch
    }

    @discardableResult
    mutating func feedLost(frames: Int = 1) -> [PointerIntent] {
        var batch: [PointerIntent] = []
        for _ in 0..<frames {
            batch += engine.consume(HandPoseFrame(joints: [:], timestamp: timestamp))
            timestamp += dt
        }
        intents += batch
        return batch
    }
}

enum FixtureLoader {
    /// Loads `<repo>/Fixtures/<name>.json`, resolved relative to this file.
    static func frames(_ name: String) throws -> [HandPoseFrame] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // GestureEngineTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // GestureEngine
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("\(name).json")
        let fixture = try JSONDecoder().decode(HandPoseFixture.self, from: Data(contentsOf: url))
        return fixture.frames
    }
}

extension Array where Element == PointerIntent {
    var clickCount: Int {
        filter { if case .click = $0 { return true } else { return false } }.count
    }

    var moveCount: Int {
        filter { if case .moveBy = $0 { return true } else { return false } }.count
    }

    var scrollCount: Int {
        filter { if case .scrollBy = $0 { return true } else { return false } }.count
    }

    func count(of intent: PointerIntent) -> Int {
        filter { $0 == intent }.count
    }
}
