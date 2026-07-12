import ApplicationServices
import PointerControl

/// CGEvent-posting implementation of `PointerOutput` — the only place in the
/// system that synthesizes OS input events, and the swap point for a future
/// DriverKit implementation. Keep this package tiny.
public struct QuartzPointerOutput: PointerOutput {
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
        switch command {
        case .move(let point):
            try post(mouseType: .mouseMoved, at: point)
        case .buttonDown, .buttonUp, .scroll:
            // Buttons arrive in M3, scroll in M4.
            throw QuartzOutputError.unsupportedCommand(command)
        }
    }

    private func post(mouseType: CGEventType, at point: CGPoint) throws {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseType,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw QuartzOutputError.eventCreationFailed
        }
        event.post(tap: .cghidEventTap)
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
