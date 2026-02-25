//
//  TranslationModels.swift
//  Cera
//
//  Created by Oskar Pajka on 25/02/2026.
//

import Foundation

// MARK: - Recognized Text

/// A block of text recognized by the Vision OCR engine.
struct RecognizedTextBlock: Identifiable, Sendable {
    let id: UUID
    let text: String
    let confidence: Float

    init(text: String, confidence: Float) {
        self.id = UUID()
        self.text = text
        self.confidence = confidence
    }
}

// MARK: - Translation Result

/// A translated text block.
struct TranslationResult: Identifiable, Sendable {
    let id: UUID
    let originalText: String
    var translatedText: String

    init(originalText: String, translatedText: String) {
        self.id = UUID()
        self.originalText = originalText
        self.translatedText = translatedText
    }
}

// MARK: - Pipeline State

/// Describes the current state of the translation pipeline.
enum TranslationState: Sendable, Equatable {
    case idle
    case recognizing
    case translating
    case summarizing
    case done
    case error(String)
}

// MARK: - Supported Language

/// Wrapper around `Locale.Language` for use in pickers and persistence.
struct SupportedLanguage: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let localeLanguage: Locale.Language

    init(languageCode: String) {
        self.id = languageCode
        self.localeLanguage = Locale.Language(identifier: languageCode)
        self.displayName = Locale.current.localizedString(forLanguageCode: languageCode)
            ?? languageCode.uppercased()
    }

    static func == (lhs: SupportedLanguage, rhs: SupportedLanguage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Languages supported by Apple Translate for offline use.
    static let all: [SupportedLanguage] = [
        "ar", "de", "en", "es", "fr", "hi", "id", "it",
        "ja", "ko", "nl", "pl", "pt", "ru", "th", "tr",
        "uk", "vi", "zh-Hans", "zh-Hant"
    ].map { SupportedLanguage(languageCode: $0) }
}
