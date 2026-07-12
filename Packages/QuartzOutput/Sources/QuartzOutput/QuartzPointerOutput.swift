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

    public func apply(_ command: PointerCommand) throws {
        // CGEvent posting arrives with M2 (move) and M3/M4 (buttons, scroll).
        throw QuartzOutputError.notImplemented
    }
}

public enum QuartzOutputError: Error, Equatable, Sendable {
    case notImplemented
    case eventCreationFailed
}
