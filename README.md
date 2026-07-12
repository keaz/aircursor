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

## Gestures (v1)

| Gesture | Action |
| --- | --- |
| Thumb–index pinch (hold) | Engage the clutch: relative cursor movement, like a trackpad |
| Release pinch | Disengage — reposition your hand freely |
| Quick pinch–release | Left click |
| Pinch, hold, move | Drag |
| Thumb–middle pinch tap | Right click |
| Thumb–middle pinch, hold, move vertically | Scroll |

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

Tip: set `DEVELOPMENT_TEAM` in `project.yml` (or Xcode signing settings) so
the app's code-signing identity is stable and macOS remembers permission
grants across rebuilds; with ad-hoc signing you may need to re-grant after
each rebuild.

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

## Privacy

No camera frames are ever written to disk or sent anywhere. Only derived
landmark data (21 hand joints as normalized points) may be serialized, and
only for test fixtures in `Fixtures/`.
