import ApplicationServices
import GestureEngine
import PointerControl

/// CGEvent-posting implementation of `PointerOutput` — the only place in the
/// system that synthesizes OS input events, and the swap point for a future
/// DriverKit implementation. Keep this package tiny.
///
/// A class because correct event types are stateful: moves while a button is
/// held must post as `.leftMouseDragged`/`.rightMouseDragged`, so the output
/// remembers which button it pressed. State is lock-guarded.
public final class QuartzPointerOutput: PointerOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var heldButton: PointerButton?

    public init() {}

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

    /// Current pointer position in global display (CG, top-left origin)
    /// coordinates — the space `PointerCommand` uses. Anchors the clutch.
    public static func currentPointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    public func apply(_ command: PointerCommand) throws {
        try makeEvent(for: command).post(tap: .cghidEventTap)
    }

    /// Builds the CGEvent for a command and updates the held-button state.
    /// Split from `apply` so tests exercise construction without posting.
    func makeEvent(for command: PointerCommand) throws -> CGEvent {
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
            return try Self.mouseEvent(type: type, at: point, button: heldButton ?? .left)

        case .buttonDown(let button, let point):
            heldButton = button
            let type: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
            let event = try Self.mouseEvent(type: type, at: point, button: button)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            return event

        case .buttonUp(let button, let point):
            heldButton = nil
            let type: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
            let event = try Self.mouseEvent(type: type, at: point, button: button)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            return event

        case .scroll:
            // Wired in M4 with momentum phases.
            throw QuartzOutputError.unsupportedCommand(command)
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
    case unsupportedCommand(PointerCommand)
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
