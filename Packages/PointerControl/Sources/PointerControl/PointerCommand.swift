import CoreGraphics
import GestureEngine

public enum ScrollPhase: Equatable, Sendable {
    case began
    case changed
    case ended
}

/// Screen-space commands. QuartzOutput is the only consumer in v1.
public enum PointerCommand: Equatable, Sendable {
    /// Global display coordinates.
    case move(to: CGPoint)
    case buttonDown(PointerButton, at: CGPoint)
    case buttonUp(PointerButton, at: CGPoint)
    case scroll(dx: Double, dy: Double, phase: ScrollPhase)
    /// Discrete system gesture; QuartzOutput owns the key-chord mapping.
    case system(SystemAction)
}

public protocol PointerOutput: Sendable {
    func apply(_ command: PointerCommand) throws
}
