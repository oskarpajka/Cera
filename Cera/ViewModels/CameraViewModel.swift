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

/// Orchestrates the capture-and-translate pipeline.
///
/// The camera runs as a live viewfinder. When the user taps the capture
/// button the current frame is grabbed and run through OCR, optional scene
/// classification, and translation. Translation can happen locally (on-device
/// LLM or Apple Translate) or via a cloud API provider depending on the
/// user's settings.
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

    /// Set briefly to true when a cloud request falls back to local mode
    /// because there is no internet connection.
    private(set) var didFallbackOffline: Bool = false

    /// Set to true for one frame to trigger the capture flash animation.
    private(set) var showCaptureFlash: Bool = false

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

    var translationMode: TranslationMode = TranslationMode.load() {
        didSet { translationMode.save() }
    }

    // MARK: - Services

    let cameraService = CameraService()
    let translationService = TranslationService()
    let connectivity = ConnectivityMonitor()
    private let ocrService = OCRService()
    private let sceneClassifier = SceneClassifier()
    private let apiService = APITranslationService()

    // MARK: - Private State

    private var _enableSummary: Bool = {
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

    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        state = .idle
        didFallbackOffline = false

        // Trigger the flash overlay.
        showCaptureFlash = true
        withAnimation(.easeOut(duration: 0.25)) {
            showCaptureFlash = false
        }

        captureTask = Task { [weak self] in
            guard let self else { return }
            await self.processCapture()
            self.isCapturing = false
        }
    }

    func clearResults() {
        captureTask?.cancel()
        summaryText = nil
        sceneDescription = ""
        fallbackTranslation = ""
        originalText = ""
        isCapturing = false
        state = .idle
        didFallbackOffline = false
    }

    // MARK: - Translation Session

    func bindTranslationSession(_ session: TranslationSession) {
        translationService.translationSession = session
    }

    func languageDisplayName(for code: String) -> String {
        if code.isEmpty || code == "auto" { return "Auto" }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    // MARK: - Processing

    private func processCapture() async {
        guard let pixelBuffer = cameraService.latestPixelBuffer else {
            state = .error("No camera frame available")
            return
        }

        do {
            // Step 1 -- OCR
            state = .recognizing
            let hints: [String]? = sourceLanguageCode.isEmpty ? nil : [sourceLanguageCode]
            let ocrBlocks = try await ocrService.recognizeText(from: pixelBuffer, languages: hints)

            guard !ocrBlocks.isEmpty else {
                state = .error("No text detected")
                return
            }

            originalText = ocrBlocks.map(\.text).joined(separator: " ")

            // Step 2 -- Scene classification (used by the LLM path)
            let rawLabels = (try? await sceneClassifier.classify(from: pixelBuffer)) ?? []

            // Step 3 -- Translate (cloud or local)
            if case .cloud(let provider) = translationMode {
                await processCloudTranslation(provider: provider, ocrBlocks: ocrBlocks)
            } else {
                await processLocalTranslation(ocrBlocks: ocrBlocks, rawLabels: rawLabels)
            }

        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Cloud Translation Path

    private func processCloudTranslation(provider: APIProvider, ocrBlocks: [RecognizedTextBlock]) async {
        // If there is no internet, fall back to local mode automatically.
        guard connectivity.isConnected else {
            didFallbackOffline = true
            await fallbackToLocal(ocrBlocks: ocrBlocks)
            return
        }

        state = .translating
        let sourceCode = sourceLanguageCode.isEmpty ? "" : sourceLanguageCode
        let targetName = languageDisplayName(for: targetLanguageCode)

        do {
            let translated = try await apiService.translate(
                text: originalText,
                source: sourceCode,
                target: targetName,
                provider: provider
            )
            fallbackTranslation = translated
            state = .done
        } catch {
            didFallbackOffline = true
            await fallbackToLocal(ocrBlocks: ocrBlocks)
        }
    }

    /// Runs the local translation pipeline when a cloud request cannot be
    /// fulfilled. Attempts scene classification if a pixel buffer is still
    /// available.
    private func fallbackToLocal(ocrBlocks: [RecognizedTextBlock]) async {
        var labels: [String] = []
        if let buffer = cameraService.latestPixelBuffer {
            labels = (try? await sceneClassifier.classify(from: buffer)) ?? []
        }
        await processLocalTranslation(ocrBlocks: ocrBlocks, rawLabels: labels)
    }

    // MARK: - Local Translation Path

    private func processLocalTranslation(ocrBlocks: [RecognizedTextBlock], rawLabels: [String]) async {
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
                let didFallback = await runAppleTranslate(blocks: ocrBlocks)
                state = didFallback ? .done : .error("Translation failed")
            }
        } else {
            let didTranslate = await runAppleTranslate(blocks: ocrBlocks)
            state = didTranslate ? .done : .error("Translation failed")
        }
    }

    /// Direct translation via Apple Translate.
    @discardableResult
    private func runAppleTranslate(blocks: [RecognizedTextBlock]) async -> Bool {
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
