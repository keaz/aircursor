public enum PointerButton: Equatable, Sendable {
    case left
    case right
}

/// What the gesture engine decides the user means. Deltas are in normalized
/// hand-space; PointerControl owns the conversion to screen pixels.
public enum PointerIntent: Equatable, Sendable {
    /// Clutch closed — begin relative tracking.
    case engaged
    case moveBy(dx: Double, dy: Double)
    /// Clutch released.
    case disengaged
    case click(PointerButton)
    case dragBegan
    case dragEnded
    case scrollBy(dx: Double, dy: Double)
}
