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

    // MARK: - Clicks and drags (M3)

    func testClickWhileEngagedPressesAndReleasesAtVirtualPosition() {
        var mapper = makeLinearMapper(anchoredAt: CGPoint(x: 500, y: 300))
        _ = mapper.commands(for: .engaged, at: 0)
        _ = mapper.commands(for: .moveBy(dx: 0.01, dy: 0), at: dt)

        let position = CGPoint(x: 500 + 0.01 * 2000, y: 300)
        XCTAssertEqual(
            mapper.commands(for: .click(.left), at: 2 * dt),
            [.buttonDown(.left, at: position), .buttonUp(.left, at: position)]
        )
        XCTAssertTrue(mapper.isEngaged, "a click must not break the clutch")
    }

    func testRightClickWhileDisengagedUsesCurrentCursorLocation() {
        // A right tap never engages the clutch, so the mapper must ask the
        // OS where the cursor actually is.
        var mapper = makeLinearMapper(anchoredAt: CGPoint(x: 700, y: 400))
        XCTAssertEqual(
            mapper.commands(for: .click(.right), at: 0),
            [
                .buttonDown(.right, at: CGPoint(x: 700, y: 400)),
                .buttonUp(.right, at: CGPoint(x: 700, y: 400)),
            ]
        )
        XCTAssertFalse(mapper.isEngaged)
    }

    func testDragPressesOnBeginMovesAndReleasesOnEnd() {
        var mapper = makeLinearMapper(anchoredAt: CGPoint(x: 100, y: 100))
        _ = mapper.commands(for: .engaged, at: 0)

        XCTAssertEqual(
            mapper.commands(for: .dragBegan, at: dt),
            [.buttonDown(.left, at: CGPoint(x: 100, y: 100))]
        )

        let moved = movePoint(mapper.commands(for: .moveBy(dx: 0.02, dy: 0), at: 2 * dt))
        XCTAssertEqual(moved!.x, 100 + 0.02 * 2000, accuracy: 1e-9)

        XCTAssertEqual(
            mapper.commands(for: .dragEnded, at: 3 * dt),
            [.buttonUp(.left, at: CGPoint(x: 100 + 0.02 * 2000, y: 100))]
        )
    }

    func testDragEndedWhileDisengagedStillReleasesTheButton() {
        // Defensive: even if intent order is ever violated upstream, a
        // dragEnded must always produce a button-up somewhere.
        var mapper = makeLinearMapper(anchoredAt: CGPoint(x: 250, y: 250))
        XCTAssertEqual(
            mapper.commands(for: .dragEnded, at: 0),
            [.buttonUp(.left, at: CGPoint(x: 250, y: 250))]
        )
    }

    // MARK: - Scroll (M4)

    func testScrollIsUnhandledUntilM4() {
        var mapper = makeLinearMapper()
        XCTAssertEqual(mapper.commands(for: .scrollBy(dx: 0, dy: 1), at: 0), [])
    }
}
