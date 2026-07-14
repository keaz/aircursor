# Bundled hand-tracking models

Two ONNX models drive the MediaPipe-style two-stage pipeline. Both are
conversions of Google's MediaPipe Hands models (TFLite → ONNX, via tf2onnx),
redistributed by the **OpenCV Zoo** under the **Apache License 2.0**.

| File | Purpose | Source (OpenCV Zoo, Apache-2.0) | SHA-256 |
| --- | --- | --- | --- |
| `palm_detection_mediapipe.onnx` | BlazePalm hand-region detector (SSD; `classifier_palm_8/16` heads → box + score) | https://huggingface.co/opencv/palm_detection_mediapipe (`palm_detection_mediapipe_2023feb.onnx`) | `78ff51c3…57fcce7c` |
| `handpose_estimation_mediapipe.onnx` | 21-landmark model with `conv_handflag` (presence) + `conv_handedness` outputs | https://huggingface.co/opencv/handpose_estimation_mediapipe (`handpose_estimation_mediapipe_2023feb.onnx`) | `db0898ae…bef6d81c` |

FP32 (non-quantized) versions are used deliberately — the OpenCV Zoo warns
the int8 variants "may produce invalid results due to a significant drop of
accuracy."

**Reference implementation for the tensor I/O (input sizes, SSD anchor
decode, output parsing):** the OpenCV Zoo Python demos
`mp_palmdet.py` / `mp_handpose.py` in https://github.com/opencv/opencv_zoo —
O2 mirrors these, not guesses.

**License:** Apache-2.0. The upstream `LICENSE` (OpenCV Zoo) and the original
MediaPipe model card apply; the models are unmodified.
