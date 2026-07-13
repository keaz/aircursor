import CoreGraphics
import Foundation
import GestureEngine
import HandPoseCore

/// Feeds v2 pose frames at 30 fps (the recorded cameras' rate) and
/// accumulates emitted intents.
struct EngineHarness {
    var engine: GestureEngine
    private(set) var intents: [PointerIntent] = []
    private(set) var timestamp: TimeInterval = 0
    let dt = 1.0 / 30

    init(config: GestureConfig = GestureConfig()) {
        self.engine = GestureEngine(config: config)
    }

    @discardableResult
    mutating func feed(
        fingers: TestHandV2.Fingers,
        indexPinch: Double? = nil,
        center: CGPoint = CGPoint(x: 0.5, y: 0.55),
        frames: Int = 1
    ) -> [PointerIntent] {
        var batch: [PointerIntent] = []
        for _ in 0..<frames {
            let frame = HandPoseFrame(
                joints: TestHandV2.joints(center: center, fingers: fingers, indexPinch: indexPinch),
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

    // Convenience poses.
    @discardableResult
    mutating func point(center: CGPoint = CGPoint(x: 0.5, y: 0.55), frames: Int = 1) -> [PointerIntent] {
        feed(fingers: .init(index: true), center: center, frames: frames)
    }

    @discardableResult
    mutating func fist(frames: Int = 1) -> [PointerIntent] {
        feed(fingers: .init(), frames: frames)
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
    func pressCount(_ button: PointerButton? = nil) -> Int {
        filter {
            if case .pressed(let b) = $0 { return button == nil || b == button }
            return false
        }.count
    }

    func releaseCount(_ button: PointerButton? = nil) -> Int {
        filter {
            if case .released(let b) = $0 { return button == nil || b == button }
            return false
        }.count
    }

    var moveCount: Int {
        filter { if case .moveBy = $0 { return true } else { return false } }.count
    }

    var scrollCount: Int {
        filter { if case .scrollBy = $0 { return true } else { return false } }.count
    }

    func systemCount(_ action: SystemAction? = nil) -> Int {
        filter {
            if case .system(let a) = $0 { return action == nil || a == action }
            return false
        }.count
    }

    func count(of intent: PointerIntent) -> Int {
        filter { $0 == intent }.count
    }
}
