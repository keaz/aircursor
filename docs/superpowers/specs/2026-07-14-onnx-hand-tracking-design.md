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
- **O3 (validation gate):** run the new source over the committed recordings
  and compare to Vision's numbers — detection %, flicker rate (Vision:
  24/100 ROI, 1/100 full-frame), and whether the palm score separates the
  real hand from the background phantom. Adopt only if it beats Vision.
- **O4:** app wiring (menu toggle Vision ↔ ONNX), README, tuning.

## Risks

- Preprocessing (rotation-aware crop + normalize) is load-bearing; a bare
  landmark model without faithful cropping degrades badly.
- Palm SSD-anchor decode is model-specific — written against the actual
  model in O2, not guessed.
- ONNX Runtime inference must run off the main actor and be Sendable-clean
  (strict concurrency). Binary adds a few MB.
- CoreML execution provider on Apple Silicon can be slower than CPU EP for
  some ops — benchmark both in O3.
