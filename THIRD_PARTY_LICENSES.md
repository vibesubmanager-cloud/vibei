# Third-party licenses (Oriente)

Check each license before commercial distribution. This is not legal advice.

| Component | Use | License | Notes |
|---|---|---|---|
| Flutter / Dart SDK | UI | BSD-3-Clause | https://github.com/flutter/flutter |
| AndroidX CameraX | Camera | Apache-2.0 | Google |
| MediaPipe Tasks Vision | Object detection | Apache-2.0 | https://github.com/google-ai-edge/mediapipe |
| EfficientDet-Lite0 TFLite | Bundled detector | Apache-2.0 | MediaPipe model; trained on COCO (annotations CC BY 4.0) |
| Vosk API (`vosk-android`) | Offline ASR (wired; model download stub) | Apache-2.0 | https://github.com/alphacep/vosk-api |
| JNA | Vosk native bridge | Apache-2.0 | |
| Android TextToSpeech / SpeechRecognizer | Speech I/O | Platform APIs | OEM voice/language data separate |
| `flutter_riverpod` | State | MIT | |
| `permission_handler` | Permissions | MIT | |
| `shared_preferences` | Settings | BSD-3-Clause | |

## Explicitly NOT used (copyleft risk)

| Component | License | Reason avoided |
|---|---|---|
| Ultralytics YOLO11 | AGPL-3.0 (or paid enterprise) | Would force source disclosure unless enterprise license purchased |
| YOLO-World | GPL-3.0 | Copyleft |

## Planned (later steps) — verify again before bundling

| Component | Planned license |
|---|---|
| ML Kit Text Recognition (bundled) | Google ML Kit Terms of Service (proprietary; on-device) |
| OpenCV Android | Apache-2.0 |
| MediaPipe Pose / Image Embedder | Apache-2.0 |
| OmDet-Turbo (optional open-vocab) | Apache-2.0 |

Bundled model file: `packages/oriente_native/android/src/main/assets/models/efficientdet_lite0.tflite`
