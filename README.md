# Cera

Cera is an iOS camera translation app that runs entirely on-device. Point the camera at foreign text, tap capture, and get a translated summary. No internet connection, no API keys, no data leaves your phone.

When Apple Intelligence is available, Cera uses the on-device language model to produce natural summaries and scene descriptions rather than literal word-for-word translations. On devices without Apple Intelligence, it falls back to Apple's built-in Translate framework.

## How it works

1. The camera runs as a live viewfinder.
2. You tap the capture button.
3. The current frame is processed through Vision OCR to extract text.
4. Vision also classifies the scene (e.g. "restaurant menu", "street sign").
5. If Apple Intelligence is enabled, the detected text and scene labels are sent to the on-device LLM, which returns a scene description and a translated summary.
6. If Apple Intelligence is off, the text goes through Apple Translate for a direct translation.
7. Results appear in a bottom sheet. Tap "Scan Again" to dismiss and capture another frame.

All processing happens on the device. The app makes zero network requests.

## Features

- Manual capture (tap to translate, no continuous scanning)
- On-device LLM summarization with scene context (requires Apple Intelligence)
- Apple Translate fallback for devices without Apple Intelligence
- 20 offline languages via Apple Translate
- Draggable bottom sheet, expandable to full screen
- Source/target language picker with swap
- Persistent language preferences
- Scene classification fed as context to improve translation quality

## Project structure

```
Cera/
  CeraApp.swift
  Utilities/
    ContinuationGuard.swift       Thread-safe guard for async continuations
  Models/
    TranslationModels.swift        Data types (OCR blocks, results, state, languages)
  Services/
    CameraService.swift            AVCaptureSession management, frame buffering
    OCRService.swift               Vision text recognition
    SceneClassifier.swift          Vision image classification
    TranslationService.swift       LLM summarization + Apple Translate fallback
  ViewModels/
    CameraViewModel.swift          Capture pipeline orchestration
  Views/
    CameraView.swift               UIViewRepresentable camera preview
    ContentView.swift              Main screen (camera, controls, sheet)
    TranslationSheetView.swift     Results bottom sheet
    SettingsView.swift             Language and processing preferences
```

## Requirements

- iOS 26.0 or later
- Xcode 26.0 or later
- Swift 6.0
- Physical device with a camera (the simulator has no camera)

Apple Intelligence (available on iPhone 15 Pro and later) is needed for the AI summary feature. Without it, the app still works using Apple Translate.

## Building

1. Clone the repository:
   ```
   git clone https://github.com/oskarpajka/Cera.git
   ```
2. Open `Cera.xcodeproj` in Xcode.
3. Select your physical device as the run destination.
4. Build and run (`Cmd+R`).

The project has no external dependencies. Everything uses Apple frameworks (Vision, Translation, FoundationModels, AVFoundation).

On first launch, the app will ask for camera permission. If you want the AI summary feature, make sure Apple Intelligence is enabled on your device under Settings > Apple Intelligence & Siri. The on-device model may take a few minutes to download the first time.

Offline translation language packs are managed by iOS. You can download additional languages under Settings > General > Language & Region > Translation Languages.

## Privacy

- No network requests
- No API keys
- No analytics or telemetry
- No data collection
- Camera frames are processed in memory and never written to disk

## License

This project is licensed under the GNU Affero General Public License v3.0. See [LICENSE](LICENSE) for the full text.
