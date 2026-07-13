import CoreGraphics
import Foundation
import GestureEngine

/// All pointer-mapping tunables. `sensitivity` is the user-facing setting;
/// the rest are calibration constants with sane defaults.
public struct PointerConfig: Equatable, Sendable {
    /// User setting; scales every pointer-movement delta.
    public var sensitivity: Double
    /// Base scale: screen points traveled per normalized hand-space unit at
    /// gain 1.
    public var pointsPerNormalizedUnit: Double
    /// Scroll scale: pixels of scroll per normalized hand-space unit.
    /// Deltas keep hand-space sign; QuartzOutput owns wheel conventions.
    public var scrollPointsPerNormalizedUnit: Double
    public var velocityCurve: VelocityGainCurve

    public init(
        sensitivity: Double = 1.0,
        pointsPerNormalizedUnit: Double = 2000,
        scrollPointsPerNormalizedUnit: Double = 2500,
        velocityCurve: VelocityGainCurve = VelocityGainCurve()
    ) {
        self.sensitivity = sensitivity
        self.pointsPerNormalizedUnit = pointsPerNormalizedUnit
        self.scrollPointsPerNormalizedUnit = scrollPointsPerNormalizedUnit
        self.velocityCurve = velocityCurve
    }
}

/// Turns gesture intents into screen-space pointer commands. Pure state
/// machine: the current cursor position (for clutch anchoring) and the
/// display bounds are injected; no OS event code lives here.
///
/// Relative mapping with clutch: `engaged` anchors at the real cursor,
/// `moveBy` deltas are gain-scaled and accumulated from there, `disengaged`
/// freezes the cursor so the hand can reposition.
public struct PointerMapper: Sendable {
    public var config: PointerConfig
    public private(set) var displayBounds: [CGRect]

    private let currentPointerLocation: @Sendable () -> CGPoint
    /// Accumulated position while engaged; nil while disengaged.
    private var virtualPosition: CGPoint?
    private var lastEventTimestamp: TimeInterval?
    /// Whether a scroll-wheel phase sequence is open (began emitted, no
    /// ended yet).
    private var scrollInProgress = false
    /// Where an unengaged press landed, so its release lands there too.
    private var unengagedPressPositions: [PointerButton: CGPoint] = [:]

    public var isEngaged: Bool { virtualPosition != nil }

    public init(
        config: PointerConfig = PointerConfig(),
        displayBounds: [CGRect],
        currentPointerLocation: @escaping @Sendable () -> CGPoint
    ) {
        self.config = config
        self.displayBounds = displayBounds
        self.currentPointerLocation = currentPointerLocation
    }

    /// Consumes one intent and returns the commands it implies, in order.
    /// Timestamps come from the frame clock and drive the velocity estimate.
    public mutating func commands(
        for intent: PointerIntent, at timestamp: TimeInterval
    ) -> [PointerCommand] {
        switch intent {
        case .engaged:
            virtualPosition = currentPointerLocation()
            lastEventTimestamp = timestamp
            return []

        case .disengaged:
            virtualPosition = nil
            lastEventTimestamp = nil
            return []

        case .moveBy(let dx, let dy):
            guard var position = virtualPosition else { return [] }

            let dt = lastEventTimestamp.map { timestamp - $0 } ?? 0
            lastEventTimestamp = timestamp
            let speed = dt > 0 ? (dx * dx + dy * dy).squareRoot() / dt : 0
            let gain = config.sensitivity
                * config.pointsPerNormalizedUnit
                * config.velocityCurve.gain(forSpeed: speed)

            position.x += dx * gain
            position.y += dy * gain
            position = Self.clamp(position, toUnionOf: displayBounds)
            virtualPosition = position
            return [.move(to: position)]

        case .pressed(let button):
            // A two-finger right tap arrives without engagement; press
            // wherever the cursor actually is and remember the spot.
            if let position = virtualPosition {
                return [.buttonDown(button, at: position)]
            }
            let position = currentPointerLocation()
            unengagedPressPositions[button] = position
            return [.buttonDown(button, at: position)]

        case .released(let button):
            let position = virtualPosition
                ?? unengagedPressPositions.removeValue(forKey: button)
                ?? currentPointerLocation()
            return [.buttonUp(button, at: position)]

        case .system(let action):
            return [.system(action)]

        case .scrollBy(let dx, let dy):
            let phase: ScrollPhase = scrollInProgress ? .changed : .began
            scrollInProgress = true
            let scale = config.scrollPointsPerNormalizedUnit
            return [.scroll(dx: dx * scale, dy: dy * scale, phase: phase)]

        case .scrollEnded:
            guard scrollInProgress else { return [] }
            scrollInProgress = false
            return [.scroll(dx: 0, dy: 0, phase: .ended)]
        }
    }

    /// Applies a new display configuration. If the engaged position fell off
    /// the remaining displays, it is pulled back and a move is emitted.
    public mutating func displayConfigurationChanged(_ bounds: [CGRect]) -> [PointerCommand] {
        displayBounds = bounds
        guard let position = virtualPosition else { return [] }

        let clamped = Self.clamp(position, toUnionOf: bounds)
        guard clamped != position else { return [] }
        virtualPosition = clamped
        return [.move(to: clamped)]
    }

    /// Clamps into the union of display rects: a point inside any display is
    /// untouched; otherwise it moves to the nearest in-bounds point. Max
    /// edges are inset by one point so the cursor stays on the pixel grid.
    static func clamp(_ point: CGPoint, toUnionOf rects: [CGRect]) -> CGPoint {
        guard !rects.isEmpty else { return point }

        var best = point
        var bestDistance = Double.infinity
        for rect in rects {
            let candidate = CGPoint(
                x: min(max(point.x, rect.minX), rect.maxX - 1),
                y: min(max(point.y, rect.minY), rect.maxY - 1)
            )
            let dx = candidate.x - point.x
            let dy = candidate.y - point.y
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }
}
