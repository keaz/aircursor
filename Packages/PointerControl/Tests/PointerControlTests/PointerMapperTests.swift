import CoreGraphics
import GestureEngine
import PointerControl
import XCTest

/// Serves the mapper a scripted sequence of "current cursor" positions.
private final class LocationStub: @unchecked Sendable {
    private var upcoming: [CGPoint]

    init(_ locations: CGPoint...) {
        self.upcoming = locations
    }

    func next() -> CGPoint {
        upcoming.isEmpty ? .zero : upcoming.removeFirst()
    }
}

final class PointerMapperTests: XCTestCase {
    private let dt = 1.0 / 60
    private let mainDisplay = CGRect(x: 0, y: 0, width: 1000, height: 600)

    /// Flat velocity curve → delta_px = d · sensitivity · pointsPerUnit.
    private func makeLinearMapper(
        anchoredAt anchor: CGPoint = CGPoint(x: 500, y: 300),
        bounds: [CGRect]? = nil,
        sensitivity: Double = 1
    ) -> PointerMapper {
        var config = PointerConfig()
        config.sensitivity = sensitivity
        config.pointsPerNormalizedUnit = 2000
        config.velocityCurve = VelocityGainCurve(maxGain: 1, halfSpeed: 1)
        let stub = LocationStub(anchor)
        return PointerMapper(
            config: config,
            displayBounds: bounds ?? [mainDisplay],
            currentPointerLocation: { stub.next() }
        )
    }

    private func movePoint(_ commands: [PointerCommand]) -> CGPoint? {
        guard case .move(let point)? = commands.first, commands.count == 1 else { return nil }
        return point
    }

    // MARK: - Clutch

    func testMoveWithoutEngageEmitsNothing() {
        var mapper = makeLinearMapper()
        XCTAssertEqual(mapper.commands(for: .moveBy(dx: 0.1, dy: 0.1), at: 0), [])
        XCTAssertFalse(mapper.isEngaged)
    }

    func testEngageAnchorsAtCurrentCursorAndEmitsNothing() {
        var mapper = makeLinearMapper(anchoredAt: CGPoint(x: 500, y: 300))
        XCTAssertEqual(mapper.commands(for: .engaged, at: 0), [])
        XCTAssertTrue(mapper.isEngaged)

        let point = movePoint(mapper.commands(for: .moveBy(dx: 0.01, dy: 0.02), at: dt))
        XCTAssertNotNil(point)
        XCTAssertEqual(point!.x, 500 + 0.01 * 2000, accuracy: 1e-9)
        XCTAssertEqual(point!.y, 300 + 0.02 * 2000, accuracy: 1e-9)
    }

    func testMovesAccumulateFromTheAnchor() {
        var mapper = makeLinearMapper(anchoredAt: CGPoint(x: 100, y: 100))
        _ = mapper.commands(for: .engaged, at: 0)
        _ = mapper.commands(for: .moveBy(dx: 0.05, dy: 0), at: dt)
        let point = movePoint(mapper.commands(for: .moveBy(dx: 0.05, dy: 0.01), at: 2 * dt))

        XCTAssertEqual(point!.x, 100 + 0.10 * 2000, accuracy: 1e-9)
        XCTAssertEqual(point!.y, 100 + 0.01 * 2000, accuracy: 1e-9)
    }

    func testSensitivityScalesDeltas() {
        var mapper = makeLinearMapper(anchoredAt: CGPoint(x: 100, y: 100), sensitivity: 2)
        _ = mapper.commands(for: .engaged, at: 0)
        let point = movePoint(mapper.commands(for: .moveBy(dx: 0.01, dy: 0), at: dt))
        XCTAssertEqual(point!.x, 100 + 0.01 * 2000 * 2, accuracy: 1e-9)
    }

    func testDisengageStopsMovementAndReengageReanchors() {
        let stub = LocationStub(CGPoint(x: 100, y: 100), CGPoint(x: 800, y: 500))
        var config = PointerConfig()
        config.pointsPerNormalizedUnit = 2000
        config.velocityCurve = VelocityGainCurve(maxGain: 1, halfSpeed: 1)
        var mapper = PointerMapper(
            config: config,
            displayBounds: [mainDisplay],
            currentPointerLocation: { stub.next() }
        )

        _ = mapper.commands(for: .engaged, at: 0)
        _ = mapper.commands(for: .moveBy(dx: 0.01, dy: 0), at: dt)
        XCTAssertEqual(mapper.commands(for: .disengaged, at: 2 * dt), [])
        XCTAssertFalse(mapper.isEngaged)
        XCTAssertEqual(mapper.commands(for: .moveBy(dx: 0.01, dy: 0), at: 3 * dt), [])

        // Re-engage: the user repositioned; the hand controls from the
        // cursor's *new* location, wherever the stub says it now is.
        _ = mapper.commands(for: .engaged, at: 4 * dt)
        let point = movePoint(mapper.commands(for: .moveBy(dx: 0.01, dy: 0), at: 5 * dt))
        XCTAssertEqual(point!.x, 800 + 0.01 * 2000, accuracy: 1e-9)
        XCTAssertEqual(point!.y, 500, accuracy: 1e-9)
    }

    // MARK: - Velocity gain

    func testVelocityGainAppliesAnalytically() {
        var config = PointerConfig()
        config.sensitivity = 1
        config.pointsPerNormalizedUnit = 2000
        config.velocityCurve = VelocityGainCurve(maxGain: 2, halfSpeed: 1)
        let stub = LocationStub(CGPoint(x: 100, y: 100))
        var mapper = PointerMapper(
            config: config,
            displayBounds: [CGRect(x: 0, y: 0, width: 5000, height: 5000)],
            currentPointerLocation: { stub.next() }
        )

        _ = mapper.commands(for: .engaged, at: 0)
        // dx 0.1 over one 60 Hz frame → speed 6 units/s →
        // gain = 1 + 6²/(6²+1²) = 1 + 36/37.
        let point = movePoint(mapper.commands(for: .moveBy(dx: 0.1, dy: 0), at: dt))
        let expectedGain = 1.0 + 36.0 / 37.0
        XCTAssertEqual(point!.x, 100 + 0.1 * 2000 * expectedGain, accuracy: 1e-6)
    }

    // MARK: - Display clamping

    func testClampsToDisplayEdge() {
        var mapper = makeLinearMapper(anchoredAt: CGPoint(x: 990, y: 300))
        _ = mapper.commands(for: .engaged, at: 0)
        // +200 px would land at x=1190, past the 1000-wide display.
        let point = movePoint(mapper.commands(for: .moveBy(dx: 0.1, dy: 0), at: dt))
        XCTAssertEqual(point!.x, 999, accuracy: 1e-9)
        XCTAssertEqual(point!.y, 300, accuracy: 1e-9)
    }

    func testCursorCrossesIntoAdjacentDisplay() {
        let second = CGRect(x: 1000, y: 0, width: 1000, height: 600)
        var mapper = makeLinearMapper(
            anchoredAt: CGPoint(x: 990, y: 300),
            bounds: [mainDisplay, second]
        )
        _ = mapper.commands(for: .engaged, at: 0)
        let point = movePoint(mapper.commands(for: .moveBy(dx: 0.02, dy: 0), at: dt))
        XCTAssertEqual(point!.x, 1030, accuracy: 1e-9, "union of displays must be reachable")
    }

    func testClampsToNearestDisplayInNonRectangularUnion() {
        // Second display is taller; a point under the first display's bottom
        // edge must clamp up to it, not sideways to the distant tall one.
        let tall = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        var mapper = makeLinearMapper(
            anchoredAt: CGPoint(x: 500, y: 590),
            bounds: [mainDisplay, tall]
        )
        _ = mapper.commands(for: .engaged, at: 0)
        let point = movePoint(mapper.commands(for: .moveBy(dx: 0, dy: 0.1), at: dt))
        XCTAssertEqual(point!.x, 500, accuracy: 1e-9)
        XCTAssertEqual(point!.y, 599, accuracy: 1e-9)
    }

    func testStuckPositionSlidesAlongEdgeAfterClamp() {
        // After clamping at the right edge, a leftward move must take effect
        // immediately — the virtual position must not have run past the edge.
        var mapper = makeLinearMapper(anchoredAt: CGPoint(x: 990, y: 300))
        _ = mapper.commands(for: .engaged, at: 0)
        _ = mapper.commands(for: .moveBy(dx: 0.5, dy: 0), at: dt) // way past the edge
        let point = movePoint(mapper.commands(for: .moveBy(dx: -0.01, dy: 0), at: 2 * dt))
        XCTAssertEqual(point!.x, 999 - 0.01 * 2000, accuracy: 1e-9)
    }

    // MARK: - Display configuration changes

    func testDisplayChangeReclampsEngagedPosition() {
        let second = CGRect(x: 1000, y: 0, width: 1000, height: 600)
        var mapper = makeLinearMapper(
            anchoredAt: CGPoint(x: 1500, y: 300),
            bounds: [mainDisplay, second]
        )
        _ = mapper.commands(for: .engaged, at: 0)

        // The second display unplugs.
        let commands = mapper.displayConfigurationChanged([mainDisplay])
        let point = movePoint(commands)
        XCTAssertEqual(point!.x, 999, accuracy: 1e-9)
        XCTAssertEqual(point!.y, 300, accuracy: 1e-9)

        // Subsequent movement accumulates from the re-clamped position.
        let next = movePoint(mapper.commands(for: .moveBy(dx: -0.01, dy: 0), at: dt))
        XCTAssertEqual(next!.x, 999 - 0.01 * 2000, accuracy: 1e-9)
    }

    func testDisplayChangeWhileDisengagedEmitsNothing() {
        var mapper = makeLinearMapper()
        XCTAssertEqual(mapper.displayConfigurationChanged([mainDisplay]), [])
    }

    // MARK: - Presses (v2: the pinch is the button)

    func testPressAndReleaseAtTheVirtualPositionWhileEngaged() {
        var mapper = makeLinearMapper(anchoredAt: CGPoint(x: 500, y: 300))
        _ = mapper.commands(for: .engaged, at: 0)
        _ = mapper.commands(for: .moveBy(dx: 0.01, dy: 0), at: dt)

        let position = CGPoint(x: 500 + 0.01 * 2000, y: 300)
        XCTAssertEqual(
            mapper.commands(for: .pressed(.left), at: 2 * dt),
            [.buttonDown(.left, at: position)]
        )

        let moved = movePoint(mapper.commands(for: .moveBy(dx: 0.02, dy: 0), at: 3 * dt))
        XCTAssertEqual(moved!.x, position.x + 0.02 * 2000, accuracy: 1e-9, "drag moves keep flowing")

        XCTAssertEqual(
            mapper.commands(for: .released(.left), at: 4 * dt),
            [.buttonUp(.left, at: CGPoint(x: position.x + 0.02 * 2000, y: 300))]
        )
        XCTAssertTrue(mapper.isEngaged, "a press pair must not break the clutch")
    }

    func testRightTapWhileDisengagedUsesCurrentCursorLocation() {
        // A two-finger tap never engages the clutch, so the mapper must ask
        // the OS where the cursor actually is.
        var mapper = makeLinearMapper(anchoredAt: CGPoint(x: 700, y: 400))
        XCTAssertEqual(
            mapper.commands(for: .pressed(.right), at: 0),
            [.buttonDown(.right, at: CGPoint(x: 700, y: 400))]
        )
        XCTAssertEqual(
            mapper.commands(for: .released(.right), at: dt),
            [.buttonUp(.right, at: CGPoint(x: 700, y: 400))]
        )
        XCTAssertFalse(mapper.isEngaged)
    }

    // MARK: - System actions pass through

    func testSystemActionsPassThroughUntouched() {
        var mapper = makeLinearMapper()
        XCTAssertEqual(mapper.commands(for: .system(.spaceLeft), at: 0), [.system(.spaceLeft)])
        XCTAssertEqual(mapper.commands(for: .system(.missionControl), at: dt), [.system(.missionControl)])
        XCTAssertEqual(mapper.commands(for: .system(.zoomStepIn), at: 2 * dt), [.system(.zoomStepIn)])
    }

    // MARK: - Scroll (M4)

    private func scrollCommand(_ commands: [PointerCommand]) -> (dx: Double, dy: Double, phase: ScrollPhase)? {
        guard case .scroll(let dx, let dy, let phase)? = commands.first, commands.count == 1 else {
            return nil
        }
        return (dx, dy, phase)
    }

    func testScrollSequencePhasesBeganChangedEnded() throws {
        var mapper = makeLinearMapper()

        let first = try XCTUnwrap(scrollCommand(mapper.commands(for: .scrollBy(dx: 0, dy: -0.01), at: 0)))
        XCTAssertEqual(first.phase, .began)

        let second = try XCTUnwrap(scrollCommand(mapper.commands(for: .scrollBy(dx: 0, dy: -0.01), at: dt)))
        XCTAssertEqual(second.phase, .changed)

        let third = try XCTUnwrap(scrollCommand(mapper.commands(for: .scrollBy(dx: 0.002, dy: -0.01), at: 2 * dt)))
        XCTAssertEqual(third.phase, .changed)

        let ended = try XCTUnwrap(scrollCommand(mapper.commands(for: .scrollEnded, at: 3 * dt)))
        XCTAssertEqual(ended.phase, .ended)
        XCTAssertEqual(ended.dx, 0)
        XCTAssertEqual(ended.dy, 0)

        // A fresh sequence begins again.
        let restarted = try XCTUnwrap(scrollCommand(mapper.commands(for: .scrollBy(dx: 0, dy: 0.01), at: 4 * dt)))
        XCTAssertEqual(restarted.phase, .began)
    }

    func testScrollDeltasScaleByScrollPointsPerUnit() throws {
        var config = PointerConfig()
        config.scrollPointsPerNormalizedUnit = 3000
        config.velocityCurve = VelocityGainCurve(maxGain: 1, halfSpeed: 1)
        let stub = LocationStub(CGPoint(x: 0, y: 0))
        var mapper = PointerMapper(
            config: config,
            displayBounds: [mainDisplay],
            currentPointerLocation: { stub.next() }
        )

        let scroll = try XCTUnwrap(scrollCommand(mapper.commands(for: .scrollBy(dx: 0.002, dy: -0.01), at: 0)))
        XCTAssertEqual(scroll.dx, 0.002 * 3000, accuracy: 1e-9)
        XCTAssertEqual(scroll.dy, -0.01 * 3000, accuracy: 1e-9)
    }

    func testScrollEndedWithoutActiveSequenceEmitsNothing() {
        var mapper = makeLinearMapper()
        XCTAssertEqual(mapper.commands(for: .scrollEnded, at: 0), [])
    }
}
