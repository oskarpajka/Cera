# Cera

Cera is an iOS camera translation app. Point the camera at foreign text, tap capture, and get a translation. It works fully offline out of the box, with optional cloud API support for OpenAI, Claude, Gemini, and DeepL.

## How it works

1. The camera runs as a live viewfinder.
2. Tap the capture button. A brief flash confirms the frame was grabbed.
3. Vision OCR extracts text from the captured frame.
4. Vision classifies the scene (e.g. "restaurant menu", "street sign") and passes the labels as context.
5. The text is translated using one of three paths:
   - **On-device LLM** (default when Apple Intelligence is available): produces a natural summary and a scene description in one pass.
   - **Apple Translate** (fallback when the LLM is unavailable): direct offline translation.
   - **Cloud API** (optional): sends the text to OpenAI, Claude, Gemini, or DeepL. Falls back to local mode automatically when offline.
6. Results appear in a draggable bottom sheet. Tap "Scan Again" to dismiss and capture another frame.

## Cloud translation (optional)

Cera ships as a fully offline app. If you want to use a cloud provider instead:

1. Open Settings (gear icon) and switch the mode to **Cloud API**.
2. Pick a provider: OpenAI, Claude, Gemini, or DeepL.
3. Enter your API key. It is stored in the device Keychain, never in plain text.
4. Tap **Verify** to confirm the key works.

When a cloud provider is selected but the device has no internet connection, Cera falls back to local translation automatically and shows a brief notice.

### Supported providers

| Provider | Model / Endpoint                           |
|----------|--------------------------------------------|
| OpenAI   | `gpt-4o-mini` via Chat Completions API     |
| Claude   | `claude-sonnet-4-20250514` via Messages API      |
| Gemini   | `gemini-2.0-flash` via GenerateContent API |
| DeepL    | `/v2/translate` (free and pro keys)        |

## Features

- Manual capture with visual flash feedback
- On-device LLM summarization with scene context (Apple Intelligence)
- Apple Translate fallback (20 offline languages)
- Cloud API translation via OpenAI, Claude, Gemini, and DeepL
- Automatic offline fallback with connectivity monitoring
- API keys stored in Keychain with one-tap verification
- Draggable bottom sheet, expandable to full screen
- Source/target language picker with swap
- Persistent preferences

## Project structure

```
Cera/
  CeraApp.swift                    App entry point
  Models/
    TranslationModels.swift        Data types (OCR blocks, results, state, languages)
    APIProvider.swift              Cloud provider enum, translation mode, persistence
  Services/
    CameraService.swift            AVCaptureSession management, frame buffering
    OCRService.swift               Vision text recognition
    SceneClassifier.swift          Vision image classification
    TranslationService.swift       On-device LLM summarization + Apple Translate
    APITranslationService.swift    Cloud API calls (OpenAI, Claude, Gemini, DeepL)
    KeychainService.swift          Secure API key storage via Security framework
    ConnectivityMonitor.swift      Network reachability via NWPathMonitor
  Utilities/
    ContinuationGuard.swift        Thread-safe guard for async continuations
  ViewModels/
    CameraViewModel.swift          Capture pipeline orchestration
  Views/
    CameraView.swift               UIViewRepresentable camera preview
    ContentView.swift              Main screen (camera, controls, sheet, flash)
    TranslationSheetView.swift     Results bottom sheet
    SettingsView.swift             Language, mode, API key, and processing settings
```

## Requirements

- iOS 26.0 or later
- Xcode 26.0 or later
- Swift 6.0
- Physical device with a camera (the simulator has no camera)

Apple Intelligence (iPhone 15 Pro and later) is needed for the AI summary feature. Without it, the app works using Apple Translate or a cloud provider.

## Building

1. Clone the repository:
   ```
   git clone https://github.com/oskarpajka/Cera.git
   ```
2. Open `Cera.xcodeproj` in Xcode.
3. Select your physical device as the run destination.
4. Build and run.

No external dependencies. Everything uses Apple frameworks (Vision, Translation, FoundationModels, AVFoundation, Network, Security).

Offline translation packs are managed by iOS under Settings > General > Language & Region > Translation Languages.

## Privacy

- **Local mode**: No network requests. All processing happens on-device. Camera frames are processed in memory and never written to disk.
- **Cloud mode**: Only the recognized text is sent to the selected API provider. No images, no metadata, no telemetry.
- API keys are stored in the device Keychain and never leave the device.
- No analytics or data collection.

## License

This project is licensed under the GNU Affero General Public License v3.0. See [LICENSE](LICENSE) for the full text.
