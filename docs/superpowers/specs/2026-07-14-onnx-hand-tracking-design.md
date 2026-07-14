# ONNX Runtime + MediaPipe-origin Hand Tracking

**Date:** 2026-07-14 · **Branch:** `feature/onnx-hand-tracking` · **Status:** in progress
**Decision:** replace/augment the Vision hand source with a MediaPipe-style
two-stage pipeline (palm detector → landmark model) run through ONNX Runtime,
to gain the two things Vision structurally lacks (measured): a real
hand-presence score, and proper frame-to-frame tracking.

## Why (measured, not speculative)

- Vision's `observation.confidence` is pinned at 1.00 even on the background
  phantom → no usable presence gate.
- Vision has no tracking; constraining it to a tight ROI made detection 24×
  worse (its landmark model needs full-frame context). MediaPipe's landmark
  model is trained on tight hand crops, so detect-once-then-track works.

## Architecture — everything behind the existing seam

The engine, filters, mapper, output, and their ~150 tests do **not** change.
The new tracker is one more `HandPoseSource` emitting the same
`HandPoseFrame` (top-left origin, mirrored). New package `OnnxHandTracking`,
two targets so the model-independent logic is testable without the binary:

```
Packages/OnnxHandTracking/
  Sources/HandLandmarkPipeline/     # PURE, no ONNX dep — fully unit-tested
    HandLandmarkModel.swift         #   PalmDetector / HandLandmarker protocols + result types
    MediaPipeLandmarks.swift        #   21-index → HandJoint map + HandPoseFrame conversion
    HandCropGeometry.swift          #   palm box / prior landmarks → crop rect (rotation-aware)
    HandTrackingPipeline.swift      #   detect-vs-track orchestration state machine (presence-gated)
  Sources/OnnxHandTracking/         # ONNX-dependent seam
    OnnxRuntimeModels.swift         #   PalmDetector/HandLandmarker via ONNX Runtime
    OnnxHandPoseSource.swift        #   AVCapture → pipeline → HandPoseFrame stream (HandPoseSource)
  Tests/HandLandmarkPipelineTests/  # pure pipeline coverage
```

## The two-stage pipeline (what HandTrackingPipeline orchestrates)

1. **No active track:** run the palm detector on the full frame. Its
   detection score is the presence gate — below threshold ⇒ emit an
   empty frame (no hand), like the Vision source does on loss.
2. **From a palm box:** derive a rotation-aligned crop (MediaPipe uses the
   wrist→middle-MCP vector for scale/rotation), run the landmark model on
   that crop, map the 21 landmarks back to full-frame + into HandPoseFrame.
3. **Active track:** on the next frame, re-derive the crop from the previous
   landmarks (skip the palm detector) and run the landmark model. The
   landmark model's own presence score decides whether the track survives;
   on loss, fall back to the palm detector next frame.

## Coordinate contract

MediaPipe landmark models output normalized `[0,1]` coords, top-left origin,
in the *crop's* space. Convert: crop-space → full-frame (apply the inverse
crop affine) → HandPoseFrame space (mirror x, as the Vision path does; the
camera preview is already mirrored). All pure and tested.

## Model acquisition (USER step — licensing + download)

The `.onnx` weights are **not** committed and must be sourced deliberately:
- Palm detector + 21-landmark models of MediaPipe origin, **Apache-2.0**
  (e.g. PINTO0309's model zoo). **Avoid the GPL-3.0 GoldYOLO variant** — it
  cannot be linked into a shipped closed app.
- Place under `Packages/OnnxHandTracking/Sources/OnnxHandTracking/Resources/`
  (SPM `.copy` resource) and verify each file's license.
- Add the `onnxruntime-swift-package-manager` SPM dependency (macOS 14,
  prebuilt binary) once the models are in hand — this is the approved
  third-party dependency (overrides CLAUDE.md's freeze for this branch).

## Milestones

- **O1 — DONE:** pure `HandLandmarkPipeline` — `HandDetectionModel`
  protocol, MediaPipe 21-landmark → `HandJoint` mapping + HandPoseFrame
  conversion, rotation-free crop geometry, and the detect/track
  orchestration (presence-gated at both stages). 19 unit tests green with a
  scripted fake model. `OnnxHandLandmarkModel` skeleton throws
  `modelNotConfigured` until O2.
- **O2 (needs model files):** implement the ONNX tensor I/O against the real
  model specs (input shapes, output tensor names, palm SSD-anchor decode);
  wire `OnnxHandPoseSource`.
- **O2 — DONE:** ONNX tensor I/O implemented against the real model specs.
  Palm `Identity`=2016×18 regression + `Identity_1`=2016 scores; hand
  `Identity`=63 screen landmarks + `Identity_1`=presence (verified by loading
  the files). `PixelPreprocessor` (CVPixelBuffer → NHWC RGB float32) pinned by
  a two-tone orientation/channel test. 38 package tests green.
- **O3 (validation gate) — DONE. VERDICT: DO NOT ADOPT.** A scratch harness
  (`scratchpad/onnxvalidate`) ran `HandTrackingPipeline<OnnxHandLandmarkModel>`
  over the 7 ground-truth gesture clips + the problem screen recording, vs
  Vision `RecordedSession` baselines on the same clips. Findings:
  - Pixel-square crops were essential (74–100%→96–100% on 5/7 clips); the
    stretch/letterbox variants both flickered badly. Kept as the real fix.
  - **Vision ≥ ONNX on every clip.** Clean clips: Vision 100%/0 everywhere;
    ONNX 100%/0 on 5/7 but flickers on the two fast swipes (swipe-left
    86%/16.4, swipe-right 95%/7.5). Vision holds ~100%/≤1 even there.
  - **The phantom-rejection premise is refuted.** Per-frame agreement on the
    problem clip: 878/900 agree, incl. 276 both-none frames — Vision does NOT
    over-detect when there is no hand. Disagreements are ONNX *missing* hands
    Vision catches (Vision-only 21 vs ONNX-only 1; swipe-left Vision-only 24 vs
    ONNX-only 0). Vision's binary detect gate already separates hand/no-hand as
    well as ONNX's graded palm score, and agrees with it.
  - ONNX also costs ~2× per frame (two model inferences).
  Conclusion: the graded-presence advantage that motivated the swap does not
  materialise on real footage, and ONNX regresses fast-motion stability. The
  user's original "recognition broken" complaint was the ROI change (reverted
  in f1ba984, main = full-frame Vision), which this data shows is already the
  strong baseline. **Recommend not wiring ONNX into the app (skip O4);** keep
  the branch as a well-tested spike in case rotation-aware MediaPipe landmarks
  or a graded gate are needed for a future scenario this footage doesn't cover.
- **O4 — NOT PURSUED** (see O3 verdict). Would be: app wiring (menu toggle
  Vision ↔ ONNX), README, tuning — only if a future need overturns the gate.

## Risks

- Preprocessing (rotation-aware crop + normalize) is load-bearing; a bare
  landmark model without faithful cropping degrades badly.
- Palm SSD-anchor decode is model-specific — written against the actual
  model in O2, not guessed.
- ONNX Runtime inference must run off the main actor and be Sendable-clean
  (strict concurrency). Binary adds a few MB.
- CoreML execution provider on Apple Silicon can be slower than CPU EP for
  some ops — benchmark both in O3.
