//
//  CameraViewModel.swift
//  Cera
//
//  Created by Oskar Pajka on 25/02/2026.
//

import AVFoundation
import SwiftUI
import Translation

// MARK: - Camera ViewModel

/// Orchestrates a manual-capture translation pipeline.
///
/// The camera feed runs continuously as a viewfinder. When the user taps
/// the capture button, the current frame is grabbed and processed:
///
/// **LLM mode**: OCR → on-device LLM produces a scene description + summary.
/// **Fallback mode**: OCR → Apple Translate for a direct translation.
@Observable @MainActor
final class CameraViewModel {

    // MARK: - Preference Keys

    private enum Defaults {
        static let sourceLanguage = "sourceLanguage"
        static let targetLanguage = "targetLanguage"
        static let enableSummary  = "enableSummary"
    }

    // MARK: - Public State

    private(set) var summaryText: String?
    private(set) var sceneDescription: String = ""
    private(set) var fallbackTranslation: String = ""
    private(set) var originalText: String = ""
    private(set) var state: TranslationState = .idle
    private(set) var cameraPermission: CameraPermission = .notDetermined
    private(set) var isCapturing: Bool = false

    var isLLMAvailable: Bool { translationService.isLLMAvailable }
    var hasResults: Bool { summaryText != nil || !fallbackTranslation.isEmpty }

    // MARK: - User Settings (persisted)

    var sourceLanguageCode: String = UserDefaults.standard.string(forKey: Defaults.sourceLanguage) ?? "" {
        didSet {
            UserDefaults.standard.set(sourceLanguageCode, forKey: Defaults.sourceLanguage)
            translationService.clearCache()
        }
    }

    var targetLanguageCode: String = UserDefaults.standard.string(forKey: Defaults.targetLanguage) ?? "en" {
        didSet {
            UserDefaults.standard.set(targetLanguageCode, forKey: Defaults.targetLanguage)
            translationService.clearCache()
        }
    }

    var enableSummary: Bool {
        get { _enableSummary && isLLMAvailable }
        set {
            _enableSummary = newValue
            UserDefaults.standard.set(newValue, forKey: Defaults.enableSummary)
        }
    }

    // MARK: - Services

    let cameraService = CameraService()
    let translationService = TranslationService()
    private let ocrService = OCRService()
    private let sceneClassifier = SceneClassifier()

    // MARK: - Private State

    private var _enableSummary: Bool = {
        // Default to true on first launch; respect saved preference after that.
        let store = UserDefaults.standard
        return store.object(forKey: Defaults.enableSummary) == nil
            ? true
            : store.bool(forKey: Defaults.enableSummary)
    }()
    private var captureTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func setup() async {
        let current = CameraService.permissionStatus
        cameraPermission = current

        switch current {
        case .authorized:
            cameraService.configure()
            cameraService.start()
        case .notDetermined:
            let granted = await CameraService.requestPermission()
            cameraPermission = granted ? .authorized : .denied
            if granted {
                cameraService.configure()
                cameraService.start()
            }
        case .denied:
            break
        }
    }

    func tearDown() {
        captureTask?.cancel()
        cameraService.stop()
    }

    // MARK: - Capture

    /// Grabs the current camera frame and processes it through the pipeline.
    /// Call this when the user taps the capture button.
    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        state = .idle

        captureTask = Task { [weak self] in
            guard let self else { return }
            await self.processCapture()
            self.isCapturing = false
        }
    }

    /// Clears results so the user can capture again.
    func clearResults() {
        captureTask?.cancel()
        summaryText = nil
        sceneDescription = ""
        fallbackTranslation = ""
        originalText = ""
        isCapturing = false
        state = .idle
    }

    // MARK: - Translation Session

    func bindTranslationSession(_ session: TranslationSession) {
        translationService.translationSession = session
    }

    func languageDisplayName(for code: String) -> String {
        if code.isEmpty || code == "auto" { return "Auto" }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    // MARK: - Private

    private func processCapture() async {
        guard let pixelBuffer = cameraService.latestPixelBuffer else {
            state = .error("No camera frame available")
            return
        }

        do {
            // Step 1: OCR
            state = .recognizing
            let hints: [String]? = sourceLanguageCode.isEmpty ? nil : [sourceLanguageCode]
            let ocrBlocks = try await ocrService.recognizeText(from: pixelBuffer, languages: hints)

            guard !ocrBlocks.isEmpty else {
                state = .error("No text detected")
                return
            }

            originalText = ocrBlocks.map(\.text).joined(separator: " ")

            // Step 2: Scene classification (raw labels as LLM input)
            let rawLabels = (try? await sceneClassifier.classify(from: pixelBuffer)) ?? []

            // Step 3: Translate
            if enableSummary {
                state = .summarizing
                let targetName = languageDisplayName(for: targetLanguageCode)
                if let result = try? await translationService.summarize(
                    detectedText: originalText,
                    rawSceneLabels: rawLabels,
                    targetLanguage: targetName
                ) {
                    sceneDescription = result.sceneDescription
                    summaryText = result.summary
                    state = .done
                } else {
                    // LLM failed — try Apple Translate as fallback
                    let didFallback = await runFallbackTranslation(blocks: ocrBlocks)
                    state = didFallback ? .done : .error("Translation failed")
                }
            } else {
                let didTranslate = await runFallbackTranslation(blocks: ocrBlocks)
                state = didTranslate ? .done : .error("Translation failed")
            }

        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Attempts a direct translation via Apple Translate.
    /// Returns `true` if at least some text was translated.
    @discardableResult
    private func runFallbackTranslation(blocks: [RecognizedTextBlock]) async -> Bool {
        state = .translating
        let sourceCode = sourceLanguageCode.isEmpty ? "auto" : sourceLanguageCode
        guard let results = try? await translationService.translateFallback(
            blocks: blocks,
            source: sourceCode,
            target: targetLanguageCode
        ), !results.isEmpty else {
            return false
        }
        fallbackTranslation = results.map(\.translatedText).joined(separator: " ")
        return true
    }
}
