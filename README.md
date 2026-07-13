# AirCursor

A macOS menu bar app that tracks one hand through the built-in camera and
turns hand poses into an invisible trackpad: point to move the pointer,
pinch to click and drag, two-finger strokes to scroll, palm swipes for
Spaces, a fist-snap for Mission Control, and pinch-spread to zoom.
Everything runs on-device; camera frames never leave the process and are
never written to disk.

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

The gesture vocabulary is an invisible trackpad, built from hand *poses*
(calibrated against real recordings in `Fixtures/recorded/`):

| Gesture | How | Result |
| --- | --- | --- |
| **Move** | Point with your index finger (other fingers curled), move your hand | Cursor follows; relax or open your hand to "lift off" and reposition |
| **Click** | While pointing, pinch thumb + index and release | The pinch *is* the button: quick pinch = click, two quick pinches = double-click |
| **Drag** | While pointing, pinch, hold the pinch, move | Button stays down while pinched; release anywhere to drop |
| **Right click** | Flick into a two-finger pose (index + middle) and out, without stroking | Context menu |
| **Scroll** | Extend index + middle together, stroke up or down | Trackpad-style pixel scrolling per stroke |
| **Switch Spaces** | Open palm, flick left or right | ctrl+← / ctrl+→ |
| **Mission Control** | Snap a fist open into all five fingers | ctrl+↑ |
| **Zoom in** | From a relaxed hand (not pointing), pinch, then spread thumb and index; re-close and spread again to keep zooming | ⌘+ steps |

Behaviors worth knowing:

- **Clicks only arm from pointing.** A pinch formed from a relaxed hand
  arms *zoom* instead — that separation is what makes scroll returns and
  zoom spreads unable to phantom-click.
- **Leaving zoom**: flash an open palm (or the two-finger pose), or drop
  your hand. Pointing alone deliberately does not exit zoom — a wide
  spread looks exactly like pointing to the camera.
- **Losing tracking is safe.** If your hand leaves the frame mid-drag, the
  button releases within ~100 ms. A stuck button is impossible by design.

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

- **Fixtures** in `Fixtures/recorded/` are the user's real gestures as
  landmark JSON, extracted from videos with the offline tool:
  `swift run --package-path Packages/HandTrackingKit fixture-extract <in.mov> <out.json>`.
  They drive the GestureEngine tests and calibrate every threshold; raw
  videos stay out of the repo (landmarks only, always).
- **ReplaySource** plays fixtures back as a live-like frame stream for
  camera-free development; `FrameRecorder` (and the overlay's Record button)
  captures new ones directly from live tracking.
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
