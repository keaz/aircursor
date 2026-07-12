// MotionFilters: pure, dependency-free signal-processing value types.
//
// M2 implements `OneEuroFilter` (per-axis, real-dt aware, with a 2-D point
// wrapper) and `HysteresisGate` (engage below closeThreshold, release above
// openThreshold) here. This package must never import AVFoundation, Vision,
// or CoreGraphics event APIs.
