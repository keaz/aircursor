import ApplicationServices
import GestureEngine
import PointerControl

/// CGEvent-posting implementation of `PointerOutput` — the only place in the
/// system that synthesizes OS input events, and the swap point for a future
/// DriverKit implementation. Keep this package tiny.
///
/// A class because correct events are stateful: moves while a button is held
/// post as drag events, and rapid same-spot presses escalate clickState so
/// pinch-pinch double-clicks work. State is lock-guarded.
public final class QuartzPointerOutput: PointerOutput, @unchecked Sendable {
    /// Same-button presses within this interval and radius coalesce into
    /// double/triple clicks (matches the macOS default feel).
    static let doubleClickInterval: TimeInterval = 0.5
    static let doubleClickRadius: Double = 5.0

    private let lock = NSLock()
    private let now: @Sendable () -> TimeInterval
    private var heldButton: PointerButton?
    private var lastPress: (button: PointerButton, at: CGPoint, time: TimeInterval)?
    private var clickState: Int64 = 1

    public init() {
        self.now = { CFAbsoluteTimeGetCurrent() }
    }

    /// Tests inject a controllable clock for click coalescing.
    init(now: @escaping @Sendable () -> TimeInterval) {
        self.now = now
    }

    /// Current pointer position in global display (CG, top-left origin)
    /// coordinates — the space `PointerCommand` uses. Anchors the clutch.
    public static func currentPointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Whether this process is trusted for Accessibility, which posting
    /// synthetic events to the HID event tap requires.
    public static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system Accessibility prompt. Once the user has dismissed
    /// it, re-granting must happen in System Settings; the onboarding flow
    /// deep-links there.
    @discardableResult
    public static func promptForPermission() -> Bool {
        // Literal value of kAXTrustedCheckOptionPrompt; the imported C global
        // is a mutable `var` and not concurrency-safe to reference.
        let promptKey = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    public func apply(_ command: PointerCommand) throws {
        for event in try makeEvents(for: command) {
            event.post(tap: .cghidEventTap)
        }
    }

    /// Builds the CGEvents for a command and updates held-button/click
    /// state. Split from `apply` so tests exercise construction without
    /// posting.
    func makeEvents(for command: PointerCommand) throws -> [CGEvent] {
        lock.lock()
        defer { lock.unlock() }

        switch command {
        case .move(let point):
            let type: CGEventType
            switch heldButton {
            case .left: type = .leftMouseDragged
            case .right: type = .rightMouseDragged
            case nil: type = .mouseMoved
            }
            return [try Self.mouseEvent(type: type, at: point, button: heldButton ?? .left)]

        case .buttonDown(let button, let point):
            heldButton = button
            let time = now()
            if let last = lastPress,
               last.button == button,
               time - last.time <= Self.doubleClickInterval,
               hypot(point.x - last.at.x, point.y - last.at.y) <= Self.doubleClickRadius {
                clickState += 1
            } else {
                clickState = 1
            }
            lastPress = (button, point, time)

            let type: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
            let event = try Self.mouseEvent(type: type, at: point, button: button)
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
            return [event]

        case .buttonUp(let button, let point):
            heldButton = nil
            let type: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
            let event = try Self.mouseEvent(type: type, at: point, button: button)
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
            return [event]

        case .scroll(let dx, let dy, let phase):
            // Pixel-unit ("continuous") scroll events, phased like a
            // trackpad gesture so apps apply their smooth/elastic scrolling.
            // Deltas keep hand-space sign: hand up (dy < 0) scrolls content
            // toward the document end, matching grab-the-page scrolling.
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(dy.rounded()),
                wheel2: Int32(dx.rounded()),
                wheel3: 0
            ) else {
                throw QuartzOutputError.eventCreationFailed
            }
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Self.scrollPhaseValue(phase))
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
            return [event]

        case .system(let action):
            let (keyCode, flags) = Self.keyChord(for: action)
            return try [true, false].map { isDown in
                guard let event = CGEvent(
                    keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown
                ) else {
                    throw QuartzOutputError.eventCreationFailed
                }
                event.flags = flags
                return event
            }
        }
    }

    /// Raw values of CGScrollPhase: began = 1, changed = 2, ended = 4.
    private static func scrollPhaseValue(_ phase: ScrollPhase) -> Int64 {
        switch phase {
        case .began: return 1
        case .changed: return 2
        case .ended: return 4
        }
    }

    /// System-gesture key chords (virtual key codes from HIToolbox Events.h).
    private static func keyChord(for action: SystemAction) -> (CGKeyCode, CGEventFlags) {
        switch action {
        case .spaceLeft: return (123, .maskControl)      // ctrl+←
        case .spaceRight: return (124, .maskControl)     // ctrl+→
        case .missionControl: return (126, .maskControl) // ctrl+↑
        case .zoomStepIn: return (24, .maskCommand)      // ⌘ and the =/+ key
        }
    }

    private static func mouseEvent(
        type: CGEventType, at point: CGPoint, button: PointerButton
    ) throws -> CGEvent {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button == .left ? .left : .right
        ) else {
            throw QuartzOutputError.eventCreationFailed
        }
        return event
    }
}

public enum QuartzOutputError: Error, Equatable, Sendable {
    case eventCreationFailed
}

/// Display topology, read through CoreGraphics so bounds are already in
/// global display coordinates (no AppKit flipping).
public enum QuartzDisplays {
    public static func activeDisplayBounds() -> [CGRect] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return []
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return []
        }
        return displays.prefix(Int(displayCount)).map { CGDisplayBounds($0) }
    }
}
