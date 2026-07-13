# AirCursor

A macOS menu bar app that tracks one hand through the built-in camera and
controls the system pointer — move, click, drag, right click, and scroll —
with pinch gestures. Everything runs on-device; camera frames never leave
the process and are never written to disk.

## How it works

```
Camera → HandTrackingKit → [HandPoseFrame] → MotionFilters (smoothing)
       → GestureEngine → [PointerIntent] → PointerControl
       → [PointerCommand] → QuartzOutput → macOS pointer
```

Two protocol seams (`HandPoseSource` in, `PointerOutput` out) wrap a pure,
deterministic core. Only `HandTrackingKit` (AVFoundation, Vision),
`QuartzOutput` (CGEvent), and the app target touch OS frameworks with side
effects; `MotionFilters`, `GestureEngine`, and `PointerControl` are
unit-testable value-type logic.

## Using AirCursor

Sit at a comfortable distance from the camera (roughly arm's length) with
your hand raised, palm toward the screen. Start tracking from the menu bar
icon. The icon shows state: slashed hand = missing permissions, outline =
paused, filled = tracking.

| Gesture | How | Result |
| --- | --- | --- |
| **Move** | Pinch thumb + index finger, move your hand, release to reposition | Cursor moves while pinched, like a finger on a trackpad — release and re-pinch to cover long distances |
| **Left click** | Quick thumb–index pinch tap — fast and still | Click wherever the cursor is |
| **Drag** | Pinch, hold still for a beat (~¼ s), then move | The button presses when you hold, drags as you move, releases when you release |
| **Right click** | Quick thumb–middle pinch tap | Context menu |
| **Scroll** | Thumb–middle pinch, hold (or start moving), then move vertically | Trackpad-style pixel scrolling; release to stop |

Two behaviors worth knowing:

- **Moving cancels clicking.** A pinch that travels commits to cursor
  movement — it will never click or start a drag on release. To drag, pinch
  and *hold still* first; to click, tap without moving.
- **Losing tracking is safe.** If your hand leaves the frame mid-drag, the
  button releases within ~100 ms. A stuck drag is impossible by design.

### Settings

Menu bar icon → **Settings…** (⌘,): pointer sensitivity, tap duration, and
individual on/off toggles for left click, drag, right click, and scroll.
Changes apply immediately. Pointer movement itself is always available.

### Debug overlay

Menu bar icon → **Debug Overlay…** shows the camera preview with landmark
dots, frame rate, live gesture state, and the pinch metric. **Record
Fixture** captures the landmark stream (JSON, never video) — useful for
tuning thresholds against your real hand and for engine test fixtures.

## Requirements

- macOS 14+ (Sonoma), Apple Silicon primary target
- Xcode 15.4+ (Swift 5.10+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build & run

```sh
xcodegen generate          # produces AirCursor.xcodeproj (gitignored)
open AirCursor.xcodeproj   # then run the AirCursor scheme
```

On first run, grant the two permissions the onboarding flow asks for:

1. **Camera** — hand tracking input.
2. **Accessibility** — required to move the pointer (System Settings →
   Privacy & Security → Accessibility).

Signing is pinned in `project.yml` (`DEVELOPMENT_TEAM` + Apple Development
identity) so the code signature — and therefore macOS's memory of your
permission grants — stays stable across rebuilds. Building on a different
machine? Change `DEVELOPMENT_TEAM` to your own team ID first.

## Packages

Each package builds and tests independently — CI runs exactly this:

```sh
swift test --package-path Packages/HandTrackingKit   # capture + Vision → frames
swift test --package-path Packages/MotionFilters     # One Euro, hysteresis
swift test --package-path Packages/GestureEngine     # pinch state machine
swift test --package-path Packages/PointerControl    # intents → screen space
swift test --package-path Packages/QuartzOutput      # CGEvent posting
```

The Xcode project is generated — edit `project.yml`, never the `.xcodeproj`.

## Development notes

- **Fixtures** in `Fixtures/` are synthetic landmark recordings driving the
  GestureEngine tests. Regenerate after changing the generator:
  `REGENERATE_FIXTURES=1 swift test --package-path Packages/HandTrackingKit --filter FixtureGenerationTests`
- **ReplaySource** plays fixtures back as a live-like frame stream for
  camera-free development; `FrameRecorder` (and the overlay's Record button)
  captures new ones.
- **Cursor harness**: `CURSOR_NUDGE=1 swift test --package-path
  Packages/QuartzOutput --filter CursorNudgeHarnessTests` physically nudges
  the pointer 10 pt and restores it, verifying the posting path end to end
  (requires the test host to be accessibility-trusted).

## Troubleshooting

- **Permissions look granted but nothing works** (onboarding checklist never
  clears, camera never starts) — macOS keys permission grants to the app's
  code signature; if the signature changed since you granted (different
  team, ad-hoc builds), System Settings shows stale toggles the system no
  longer honors. Reset this app's entries and re-grant:
  `tccutil reset Camera com.kasunranasinghe.AirCursor && tccutil reset
  Accessibility com.kasunranasinghe.AirCursor`, then relaunch.
- **Choppy tracking** — most built-in cameras top out at 30 fps; the overlay
  shows the real rate. Good, even lighting improves Vision's confidence.
- **Gestures trigger accidentally** — lower the tap duration, or disable
  individual gestures in Settings; keep your other fingers relaxed and apart
  so pinch metrics stay unambiguous.

## Privacy

No camera frames are ever written to disk or sent anywhere. Only derived
landmark data (21 hand joints as normalized points) may be serialized, and
only for test fixtures in `Fixtures/`.
