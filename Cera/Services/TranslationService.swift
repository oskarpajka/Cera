//
//  TranslationService.swift
//  Cera
//
//  Created by Oskar Pajka on 25/02/2026.
//

import Foundation
import Translation
import FoundationModels

// MARK: - Summary Result

/// Structured output from the on-device LLM.
struct SummaryResult: Sendable {
    /// A human-readable description of what the camera sees.
    let sceneDescription: String
    /// A natural, concise translated summary of the detected text.
    let summary: String
}

// MARK: - Translation Service

/// Translation engine with two modes:
///
/// **Primary (LLM)**: Feeds the on-device LLM the detected text, raw scene
/// classification labels, and target language. The LLM produces a rich scene
/// description and a translated summary in one pass.
///
/// **Fallback (Apple Translate)**: When Apple Intelligence is unavailable,
/// falls back to the system Translate framework for a direct translation.
@Observable
final class TranslationService {

    // MARK: - Properties

    var translationSession: TranslationSession?

    var isLLMAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    // MARK: - Translation Cache (FIFO)

    private var cache: [String: String] = [:]
    private var cacheOrder: [String] = []
    private let maxCacheSize = 200

    private func cacheKey(text: String, source: String, target: String) -> String {
        let normalizedSource = (source.isEmpty || source == "auto") ? "_auto" : source
        return "\(normalizedSource)|\(target)|\(text)"
    }

    private func insertCache(key: String, value: String) {
        if cache[key] != nil { return }
        if cache.count >= maxCacheSize, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        cache[key] = value
        cacheOrder.append(key)
    }

    // MARK: - Primary: LLM Summary + Scene Description

    /// Produces a rich scene description and a translated summary using the
    /// on-device LLM.
    ///
    /// - Parameters:
    ///   - detectedText: Raw OCR text from the camera.
    ///   - rawSceneLabels: Classification labels from Vision (e.g. `["document", "text"]`).
    ///   - targetLanguage: Human-readable target language name (e.g. "English").
    /// - Returns: A `SummaryResult` with scene description and translated summary.
    func summarize(
        detectedText: String,
        rawSceneLabels: [String],
        targetLanguage: String
    ) async throws -> SummaryResult? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        guard !detectedText.isEmpty else { return nil }

        let labelsHint = rawSceneLabels.isEmpty
            ? "no classification available"
            : rawSceneLabels.joined(separator: ", ")

        let instructions = Instructions {
            """
            You are a camera translation assistant. You receive:
            1. Text detected by OCR from a camera image.
            2. Raw image classification labels from a Vision model.
            3. A target language.

            You must produce EXACTLY two sections:

            SCENE: Write one natural sentence describing what the camera is \
            looking at. Use the classification labels as hints but describe it \
            like a human would. For example, instead of "document, text" write \
            "A printed document on a table". Be specific and descriptive.

            SUMMARY: Write a translated summary of the detected text in \
            \(targetLanguage). Do NOT translate word-by-word. Capture the key \
            meaning in natural \(targetLanguage). Use as many sentences as \
            needed to accurately convey the meaning — it could be one sentence \
            for a sign or several for a long paragraph. Use natural phrasing a \
            native \(targetLanguage) speaker would use.

            Format your response EXACTLY like this (keep the labels):
            SCENE: [your scene description]
            SUMMARY: [your translated summary]
            """
        }

        let session = LanguageModelSession(instructions: instructions)

        let prompt = """
        Classification labels: \(labelsHint)

        Detected text:
        \(detectedText)
        """

        let response = try await session.respond(to: prompt)
        return parseLLMResponse(response.content)
    }

    /// Parses the structured LLM response into a `SummaryResult`.
    private func parseLLMResponse(_ text: String) -> SummaryResult? {
        let lines = text.components(separatedBy: "\n")
        var scene = ""
        var summary = ""
        var currentSection = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SCENE:") {
                currentSection = "scene"
                scene = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("SUMMARY:") {
                currentSection = "summary"
                summary = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if !trimmed.isEmpty {
                // Continuation of current section
                switch currentSection {
                case "scene": scene += " " + trimmed
                case "summary": summary += " " + trimmed
                default: break
                }
            }
        }

        guard !summary.isEmpty else { return nil }
        return SummaryResult(
            sceneDescription: scene.isEmpty ? "" : scene,
            summary: summary
        )
    }

    // MARK: - Fallback: Apple Translate

    /// Direct translation via Apple Translate. Used when the LLM is unavailable.
    func translateFallback(
        blocks: [RecognizedTextBlock],
        source: String,
        target: String
    ) async throws -> [TranslationResult] {
        guard let session = translationSession else {
            throw TranslationError.sessionNotAvailable
        }

        var results: [TranslationResult] = []
        var uncachedBlocks: [RecognizedTextBlock] = []

        for block in blocks {
            let key = cacheKey(text: block.text, source: source, target: target)
            if let cached = cache[key] {
                results.append(TranslationResult(originalText: block.text, translatedText: cached))
            } else {
                uncachedBlocks.append(block)
            }
        }

        if !uncachedBlocks.isEmpty {
            let requests = uncachedBlocks.enumerated().map { index, block in
                TranslationSession.Request(sourceText: block.text, clientIdentifier: "\(index)")
            }

            let responses = try await session.translations(from: requests)

            for response in responses {
                guard let idString = response.clientIdentifier,
                      let index = Int(idString),
                      index < uncachedBlocks.count
                else { continue }

                let block = uncachedBlocks[index]
                let key = cacheKey(text: block.text, source: source, target: target)
                insertCache(key: key, value: response.targetText)
                results.append(TranslationResult(originalText: block.text, translatedText: response.targetText))
            }
        }

        return results
    }

    func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }
}

// MARK: - Errors

enum TranslationError: LocalizedError {
    case sessionNotAvailable

    var errorDescription: String? {
        switch self {
        case .sessionNotAvailable:
            "Translation session not available. Ensure languages are downloaded."
        }
    }
}
