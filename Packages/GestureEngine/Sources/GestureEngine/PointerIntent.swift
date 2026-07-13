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
    /// The scroll pinch released (or tracking was lost): PointerControl
    /// closes the scroll-wheel phase so apps see a completed gesture.
    /// Addition to the original v1 contract — without it the mapper cannot
    /// emit `ScrollPhase.ended` at the right moment.
    case scrollEnded
}
