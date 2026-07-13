# v2 Gesture Vocabulary — "Invisible Trackpad"

**Date:** 2026-07-13 · **Status:** approved; revised same day against the
user's recorded gestures (`Fixtures/recorded/`, extracted from videos with
`fixture-extract` — landmarks only, raw video stays out of the repo).
**Supersedes:** the v1 pinch-clutch gesture set (M0–M4), user-directed revision.

## Revision: evidence from real recordings

Seven real gesture recordings (~30 fps, 100% hand detection) calibrated the
design and forced three changes:

1. **Presses are entry-gated.** During scroll-stroke returns the relaxed
   index dips to thumb–index ratios below 0.35 (29 frames across the two
   scroll videos) — an ungated pinch would phantom-click mid-scroll. A pinch
   therefore only presses the left button when it closes **from the Point
   pose**; pinches formed from Neutral arm **zoom** instead, and pinches
   formed during Scroll/returns do nothing.
2. **Thumb–middle right-click is dead.** While pointing, the curled middle
   finger rests at thumb–middle ratio 0.16–0.34 — permanently "closed".
   Right-click is now a **two-finger tap**: enter and leave the Scroll pose
   within ≤ 0.25 s with < 0.02 scroll travel. (Right-drag is dropped.)
3. **The extras are in scope** (user recorded them): open-palm swipe
   left/right → **switch Spaces** (ctrl+←/→); fist-to-open **bloom** →
   **Mission Control** (ctrl+↑); Neutral-armed pinch **spread** →
   **zoom in** (⌘+ ratchet steps; re-close re-arms; zoom-out deferred).

Calibration from the recordings: extended fingers read 1.3–1.5, curled
0.4–0.8 → extension hysteresis extend > 1.15 / retract < 0.95 sits in the
gap; Scroll-pose purity holds (ring/little read extended ≤ 1 frame during
strokes); pointing never false-pinches (min ratio 0.45 across 216 frames);
blooms complete within ~1 frame (≤ 0.13 s window, wrist drift < 0.05);
zoom spreads peak 1.43–1.65 (arm at close, step per +0.15 above 1.0);
swipe strokes peak ~2.0 units/s with ≥ 0.09 displacement (detector: first
qualifying stroke after palm-open wins; 0.6 s cooldown swallows returns).

## Goal

Replace v1's pinch-clutch movement with pose-based control that mirrors
trackpad muscle memory: pointing moves the cursor, the pinch is the mouse
button, two fingers scroll. Single hand, on-device, sub-100 ms — the
two-seam architecture, packages, and privacy rules are unchanged.

## Interaction model (user-approved)

| Pose | Hand shape | Meaning |
| --- | --- | --- |
| **Point** | Index extended; middle, ring, little curled | Cursor moves (relative, smoothed) — "finger on the trackpad" |
| **Pinch** | Thumb–index tips closed | **Left button held**: close = down, open = up. Quick pinch = click, pinch-hold-move = drag |
| **Right-pinch** | Thumb–middle tips closed | Right button held (same press model; right-drag free) |
| **Scroll** | Index + middle extended; ring, little curled | Two-finger scroll; cursor frozen |
| **Neutral** | Anything else (open palm, fist, relaxed) | Nothing moves — "finger lifted"; reposition freely |

Key simplification vs v1: movement no longer lives on the pinch, so the
pinch maps 1:1 to a physical button. **No tap-duration/tap-movement
disambiguation exists in v2** — clicks are real down/up pairs with zero
added latency, and `tapDuration`/`tapMovement` leave `GestureConfig`.

The cursor moves in Point and in both pinch poses (that is what dragging
is); it is frozen in Neutral and Scroll.

## Pose classification (new, pure, in GestureEngine)

`PoseClassifier` — value type, own file, own tests.

- **Finger extension** (index/middle/ring/little): extended when
  `dist(tip, wrist) / dist(pip, wrist)` exceeds a threshold, with per-finger
  hysteresis to prevent boundary flicker. Defaults:
  `fingerExtendThreshold = 1.12`, `fingerRetractThreshold = 1.02`
  (extend above high, retract below low; band holds state). Constants live
  in `GestureConfig`; no additional debounce in v2.0 — hysteresis only.
- **Pinch detection**: v1's proven metrics unchanged — thumbTip-to-tip
  distance normalized by wrist–middleMCP span, hysteresis gates at
  0.35/0.55.
- **Priority** (first match wins): index-pinch → right-pinch → Scroll
  (index+middle extended, ring+little retracted) → Point (index extended,
  middle+ring+little retracted) → Neutral. The thumb never counts toward
  extension poses.
- **Missing joints**: a finger with missing joints holds its previous
  extension state; if the pinch-metric joints (wrist, middleMCP, thumbTip,
  indexTip) or the movement joint are missing, the frame is degraded and
  the v1 grace logic applies (coast ≤ 100 ms, then idle).

## Engine state machine (v2)

States: `idle`, `neutral`, `pointing`, `pressed(PointerButton)`,
`scrolling`. Emissions:

- neutral → pointing: `engaged` (mapper anchors at the real cursor).
  pointing → neutral: `disengaged`.
- Point/pressed frames emit `moveBy` deltas of the movement joint
  (`indexMCP`, One Euro-smoothed app-side as today; zero deltas suppressed).
- Entering a pinch from any pose: `engaged` first if not already engaged,
  then `pressed(button)`. Leaving it: `released(button)`, then the new
  pose's transition (`disengaged` if Neutral, nothing if Point, scroll
  entry if Scroll).
- Scroll entry: `disengaged` first if engaged; then `scrollBy` per moving
  frame. Scroll exit: `scrollEnded`, then the new pose's entry intents.
- Hand loss beyond grace, and `reset()`: emit, in order and as applicable,
  `released(button)`, `scrollEnded`, `disengaged`, then go idle.

**Safety invariant (unchanged in spirit, simpler in form):** a button is
down exactly while its pinch gate is closed; every exit path from
`pressed` — pose change, hand loss, teardown — emits `released` first.
Fixture tests enforce it.

## Intent contract (v2)

```swift
public enum SystemAction: Equatable, Sendable {
    case spaceLeft      // swipe left  → ctrl+←
    case spaceRight     // swipe right → ctrl+→
    case missionControl // bloom       → ctrl+↑
    case zoomStepIn     // pinch spread → ⌘+ (one step per ratchet increment)
}

public enum PointerIntent: Equatable, Sendable {
    case engaged
    case moveBy(dx: Double, dy: Double)
    case disengaged
    case pressed(PointerButton)   // replaces click/dragBegan
    case released(PointerButton)  // replaces dragEnded
    case scrollBy(dx: Double, dy: Double)
    case scrollEnded
    case system(SystemAction)     // discrete system gestures
}
```

`click`, `dragBegan`, `dragEnded` are removed. Two-finger-tap right-click
emits a `pressed(.right)`/`released(.right)` pair. PointerControl maps
`pressed`/`released` to `buttonDown`/`buttonUp` at the engaged virtual
position (or the live cursor position when unengaged) and passes
`system(_:)` through as a new `PointerCommand.system(SystemAction)`;
QuartzOutput owns the key-chord mapping and posts keyDown/keyUp pairs to
the HID tap. Recorded fixtures double as cross-contamination tests: every
recording asserts zero intents of every other gesture family.

## QuartzOutput: click coalescing (new)

Because clicks are now genuine down/up pairs, QuartzOutput gains repeat
detection so rapid pinches double- and triple-click: it remembers the last
button-down (button, position, time); a same-button down within
`doubleClickInterval = 0.5 s` and `doubleClickRadius = 5 pt` increments
`clickState` (1 → 2 → 3, else reset to 1). Down and its matching up carry
the same clickState. Unit-tested through `makeEvent` without posting.

## Settings

Toggles become: **left button** (click + drag), **right button**,
**scroll**; pointer movement is always on. The tap-duration slider is
removed (no such threshold exists); sensitivity is unchanged. Keys:
`gesture.leftButton.enabled`, `gesture.rightButton.enabled`,
`gesture.scroll.enabled` (registered defaults true; old keys ignored).
A disabled button suppresses its `pressed`/`released` emissions in the
engine; disabled scroll makes the Scroll pose inert.

## Fixtures and tests

`SyntheticHand` learns per-finger curl (curled tip placed near the PIP,
toward the palm) while keeping exact pinch-ratio control. All v1 gesture
fixtures are replaced (git history preserves them) by:

- `point_move` → `[engaged, moveBy…, disengaged]`
- `pinch_tap` (point → quick pinch → point) → `[engaged, pressed(.left), released(.left)]`
- `pinch_drag` (point → pinch → move → release → neutral) → `[engaged, pressed(.left), moveBy…, released(.left), disengaged]`
- `right_pinch_tap` → `[…, pressed(.right), released(.right), …]`
- `two_finger_scroll` → `[scrollBy…, scrollEnded]`
- `pose_flicker` (extension ratios oscillating inside the hysteresis band) → no pose transitions
- `hand_loss_mid_pinch` → ends `[…, released(.left), disengaged]` before idle

Plus programmatic transition tests (pose priority, pinch-from-scroll,
missing-finger hold, grace, toggles, reset). TDD discipline continues:
fixture tests written and failing before the engine changes.

## App

Overlay HUD shows the live pose name; menu status line shows it too.
README gesture table and usage text rewritten for v2.

## Out of scope (this round)

Extra gestures (swipe back/forward, Mission Control, zoom), multi-hand,
absolute mapping, pose debounce beyond hysteresis. The classifier's
finger-state output is designed so counted-finger swipe poses can be added
later without reshaping the engine.

## Risks

Pointing-pose detection is the one new recognition problem (pinches are
v1-proven). Mitigations: per-finger hysteresis, conservative defaults, the
overlay fixture recorder for tuning against the user's real hand, and
threshold constants centralized in `GestureConfig`.

## Implementation milestones

- **G1 — pose foundations:** `SyntheticHand` v2 (finger curl), `PoseClassifier` + unit tests, new fixture generation.
- **G2 — engine v2:** intent contract change, state machine rewrite, fixture + transition suites; mapper `pressed`/`released`; QuartzOutput click coalescing.
- **G3 — surface:** app wiring, HUD pose, settings rework, README, real-hand tuning session; push + CI green.
