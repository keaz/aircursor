public enum PointerButton: Equatable, Sendable {
    case left
    case right
}

/// Discrete system gestures; QuartzOutput owns their key-chord mappings.
public enum SystemAction: Equatable, Sendable {
    /// Open-palm swipe left → previous Space (ctrl+←).
    case spaceLeft
    /// Open-palm swipe right → next Space (ctrl+→).
    case spaceRight
    /// Fist-to-palm bloom → Mission Control (ctrl+↑).
    case missionControl
    /// Neutral-armed pinch spread ratchet → zoom in one step (⌘+).
    case zoomStepIn
}

/// What the gesture engine decides the user means. Deltas are in normalized
/// hand-space; PointerControl owns the conversion to screen pixels.
///
/// v2 contract: the pinch is the mouse button, so presses are real
/// down/up pairs (`pressed`/`released` replace v1's click/dragBegan/
/// dragEnded — a quick pair *is* a click, a held pair with movement *is*
/// a drag).
public enum PointerIntent: Equatable, Sendable {
    /// Pointer clutch engaged (pointing pose entered) — begin relative
    /// tracking from the cursor's current position.
    case engaged
    case moveBy(dx: Double, dy: Double)
    /// Pointer clutch released.
    case disengaged
    case pressed(PointerButton)
    case released(PointerButton)
    case scrollBy(dx: Double, dy: Double)
    /// The scroll stroke ended (pose left or tracking lost): PointerControl
    /// closes the scroll-wheel phase.
    case scrollEnded
    case system(SystemAction)
}
