# AirCursor — agent guardrails

- v1 scope is frozen: no DriverKit, no MediaPipe, no multi-hand, no gesture
  editor UI, no launch-at-login, no auto-update, no analytics. If a task seems
  to need one of these, stop and ask.
- Two-seam rule: OS frameworks with side effects live only in HandTrackingKit
  (AVFoundation, Vision) and QuartzOutput (CGEvent) and the App target.
  MotionFilters, GestureEngine, PointerControl must not import them.
- No third-party dependencies in any package without explicit approval.
  Exception (approved 2026-07-14, branch `feature/onnx-hand-tracking` only):
  ONNX Runtime + MediaPipe-origin ONNX models, to replace Vision's hand
  tracking. Confined to the new `OnnxHandTracking` package behind the
  `HandPoseSource` seam; nothing else changes. See
  docs/superpowers/specs/2026-07-14-onnx-hand-tracking-design.md.
- Strict concurrency: treat Sendable/data-race warnings as errors to fix.
- Never write camera frames or images to disk; fixtures are landmark JSON only.
- Never add entitlements, change Info.plist permission strings, or alter the
  permission flow without asking first.
- pbxproj is generated — edit project.yml and run `xcodegen generate`; never
  commit .xcodeproj.
- Every GestureEngine behavior change requires a fixture test that fails
  without the change.
- Safety invariant: a transition out of an engaged/dragging state must emit
  button-up first. Tests enforce this; do not weaken them.
- Commit per logical change; push at milestone boundaries.

## Build & test

- Packages: `swift build --package-path Packages/<Name>` and
  `swift test --package-path Packages/<Name>` (same commands CI runs).
- App: `xcodegen generate`, then open `AirCursor.xcodeproj` or
  `xcodebuild -project AirCursor.xcodeproj -scheme AirCursor build`.
- Package dependency order (all pure except the seams):
  `HandTrackingKit[HandPoseCore] ← GestureEngine ← PointerControl ← QuartzOutput`,
  with `MotionFilters` standalone (used by GestureEngine).

## Repo map

- `Packages/HandTrackingKit` — two targets: `HandPoseCore` (pure contracts:
  `HandJoint`, `HandPoseFrame`, `HandPoseSource`, replay/record) and
  `HandTrackingKit` (AVFoundation + Vision camera source).
- `Packages/MotionFilters` — One Euro filter, hysteresis gate; zero deps.
- `Packages/GestureEngine` — pure pinch state machine → `PointerIntent`.
- `Packages/PointerControl` — intents → screen-space `PointerCommand`.
- `Packages/QuartzOutput` — CGEvent posting; accessibility permission helpers.
- `App/` — SwiftUI menu bar app (`project.yml` → XcodeGen).
- `Fixtures/` — landmark JSON fixtures (never camera frames).
