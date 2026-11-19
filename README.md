# Oriente

Camera + voice guidance for blind and low-vision users. Clean-room Flutter (UI) + Kotlin (Android native) build.

**Step 2 status:** scaffold, TalkBack-oriented home button, offline command routing, and Object Search vertical slice (CameraX + MediaPipe EfficientDet-Lite0 + guidance beeps/haptics + TTS + system ASR).

## Requirements

- Flutter 3.38+ (`C:\Users\buxin\flutter` if installed by the setup in this session)
- Android SDK, minSdk 26
- Physical Android device recommended (camera + TalkBack)

```powershell
$env:PATH = "C:\Users\buxin\flutter\bin;C:\Program Files\Android\Android Studio\jbr\bin;$env:LOCALAPPDATA\Android\Sdk\platform-tools;$env:PATH"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
```

## Run

```powershell
cd apps\oriente_app
flutter pub get
flutter run
```

Grant camera and microphone when prompted. Enable TalkBack for accessibility testing.

### Try Object Search

1. Tap **TAP & SPEAK**
2. Say **find a bottle** or **find a chair** (COCO labels)
3. Sweep the camera; listen for beeps, haptics, and “left / right / closer”
4. Say **stop** or tap **Cancel**

## Layout

See `docs/STEP2.md` and `THIRD_PARTY_LICENSES.md`.

## Stubs (spoken clearly in-app)

- Scene narration, text search, document reading, identify, personal objects, venues
- Vosk model download UI (system SpeechRecognizer used for now)
- Online AI proxy client
- Pigeon codegen (typed MethodChannel facade in place)
