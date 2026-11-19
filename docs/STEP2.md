# Step 2 — Scaffold + Object Search slice

## What works

- Flutter app `apps/oriente_app` with Riverpod
- High-contrast home screen: one large **Tap & speak** control + Cancel + Settings (Semantics labeled)
- Offline intent parser (`oriente_commands`) with fuzzy helpers
- Native Android plugin modules:
  - `camera` — CameraX analysis ~8 FPS
  - `vision` — MediaPipe EfficientDet-Lite0 (bundled, Apache-2.0)
  - `guidance` — SoundPool beeps + VibrationEffect + direction phrases
  - `speech` — TextToSpeech + system SpeechRecognizer (`EXTRA_PREFER_OFFLINE`)
  - `objectsearch` — end-to-end hunt loop
- Channel contract: `oriente/methods`, `oriente/asr`, `oriente/guidance`, `oriente/session_state`

## Plain stubs / assumptions

1. **Vosk** dependency is on the classpath and `isVoskReady` checks for a model folder, but listening still uses **system SpeechRecognizer**. Spoken on launch. Full Vosk streaming + download UI = later step.
2. **Pigeon** not generated yet; typed Dart `OrienteHost` wraps MethodChannel (same contract).
3. Features 1, 3–9 (except Object Search) announce as stubs when requested by voice.
4. **Online availability** hard-coded `false` in the Dart router for this slice.
5. COCO labels only — cables/chargers will not detect until custom model (feature 5).
6. No real-device benchmark numbers yet (needs your phone + photos).

## Manual device check

1. `flutter run` on a physical device
2. Grant camera + mic
3. TalkBack on: focus should land sensibly on brand, status, big button, cancel
4. Airplane mode: Object Search still runs; speech may fail if OEM has no offline pack (expected until Vosk model ships)
5. Say “find a chair”, point at a chair, confirm beeps intensify toward center
