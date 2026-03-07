//
//  APITranslationService.swift
//  Cera
//
//  Created by Oskar Pajka on 07/03/2026.
//

import Foundation

// MARK: - API Translation Service

/// Sends text to a cloud provider for translation. Each provider has its own
/// request format, but they all boil down to: send text in, get translated
/// text out. All networking goes through URLSession with no external
/// dependencies.
final class APITranslationService: Sendable {

    // MARK: - Translate

    /// Translates text using the given cloud provider.
    ///
    /// - Parameters:
    ///   - text: The source text to translate.
    ///   - source: BCP-47 source language code, or empty for auto-detect.
    ///   - target: BCP-47 target language code.
    ///   - provider: The cloud provider to use.
    /// - Returns: The translated text.
    func translate(
        text: String,
        source: String,
        target: String,
        provider: APIProvider
    ) async throws -> String {
        guard let apiKey = KeychainService.load(key: provider.keychainKey) else {
            throw APITranslationError.missingAPIKey(provider)
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw APITranslationError.missingAPIKey(provider)
        }

        switch provider {
        case .openAI: return try await translateOpenAI(text: text, source: source, target: target, apiKey: trimmedKey)
        case .claude:  return try await translateClaude(text: text, source: source, target: target, apiKey: trimmedKey)
        case .gemini:  return try await translateGemini(text: text, source: source, target: target, apiKey: trimmedKey)
        case .deepL:   return try await translateDeepL(text: text, source: source, target: target, apiKey: trimmedKey)
        }
    }

    /// Sends a lightweight request to verify the API key works.
    func verifyKey(provider: APIProvider, apiKey: String) async -> Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        do {
            switch provider {
            case .openAI:
                // List models endpoint - fast, low cost.
                var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 10
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200

            case .claude:
                // Send a minimal message.
                var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                request.httpMethod = "POST"
                request.setValue(trimmed, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "model": "claude-sonnet-4-20250514",
                    "max_tokens": 1,
                    "messages": [["role": "user", "content": "hi"]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = 10
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200

            case .gemini:
                // List models - no request body needed.
                let urlString = "https://generativelanguage.googleapis.com/v1beta/models?key=\(trimmed)"
                var request = URLRequest(url: URL(string: urlString)!)
                request.timeoutInterval = 10
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200

            case .deepL:
                // Usage endpoint.
                var request = URLRequest(url: deeplBaseURL(for: trimmed).appendingPathComponent("v2/usage"))
                request.setValue("DeepL-Auth-Key \(trimmed)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 10
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200
            }
        } catch {
            return false
        }
    }

    // MARK: - OpenAI

    private func translateOpenAI(text: String, source: String, target: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let sourceHint = source.isEmpty ? "auto-detected" : source
        let systemPrompt = """
        You are a translation engine. Translate the user's text from \(sourceHint) to \(target). \
        Return ONLY the translated text, nothing else. No explanations, no quotes, no labels.
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.1,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: .openAI)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw APITranslationError.unexpectedResponse(.openAI)
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Claude

    private func translateClaude(text: String, source: String, target: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let sourceHint = source.isEmpty ? "auto-detected" : source
        let prompt = """
        Translate the following text from \(sourceHint) to \(target). \
        Return ONLY the translated text, nothing else.

        \(text)
        """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: .claude)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let translated = firstBlock["text"] as? String else {
            throw APITranslationError.unexpectedResponse(.claude)
        }

        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Gemini

    private func translateGemini(text: String, source: String, target: String, apiKey: String) async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw APITranslationError.unexpectedResponse(.gemini)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let sourceHint = source.isEmpty ? "auto-detected" : source
        let prompt = """
        Translate the following text from \(sourceHint) to \(target). \
        Return ONLY the translated text, nothing else.

        \(text)
        """

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: .gemini)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let contentObj = firstCandidate["content"] as? [String: Any],
              let parts = contentObj["parts"] as? [[String: Any]],
              let translated = parts.first?["text"] as? String else {
            throw APITranslationError.unexpectedResponse(.gemini)
        }

        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - DeepL

    private func translateDeepL(text: String, source: String, target: String, apiKey: String) async throws -> String {
        let base = deeplBaseURL(for: apiKey)
        let url = base.appendingPathComponent("v2/translate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body: [String: Any] = [
            "text": [text],
            "target_lang": deeplLanguageCode(target)
        ]
        if !source.isEmpty {
            body["source_lang"] = deeplLanguageCode(source)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: .deepL)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = json["translations"] as? [[String: Any]],
              let translated = translations.first?["text"] as? String else {
            throw APITranslationError.unexpectedResponse(.deepL)
        }

        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// DeepL free-tier keys end with `:fx`. Route those to the free API.
    private func deeplBaseURL(for apiKey: String) -> URL {
        let host = apiKey.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        return URL(string: "https://\(host)")!
    }

    /// DeepL uses uppercase codes and some differ from BCP-47 conventions.
    private func deeplLanguageCode(_ code: String) -> String {
        let upper = code.uppercased()
        switch upper {
        case "ZH-HANS": return "ZH-HANS"
        case "ZH-HANT": return "ZH-HANT"
        default:
            // DeepL wants just the primary subtag for most languages,
            // but full codes for Chinese variants.
            return upper.components(separatedBy: "-").first ?? upper
        }
    }

    // MARK: - Validation

    private func validateHTTPResponse(_ response: URLResponse, data: Data, provider: APIProvider) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APITranslationError.networkError(provider, "No HTTP response")
        }

        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw APITranslationError.invalidAPIKey(provider)
        case 429:
            throw APITranslationError.rateLimited(provider)
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APITranslationError.networkError(provider, "HTTP \(http.statusCode): \(body)")
        }
    }
}

// MARK: - Errors

enum APITranslationError: LocalizedError {
    case missingAPIKey(APIProvider)
    case invalidAPIKey(APIProvider)
    case rateLimited(APIProvider)
    case unexpectedResponse(APIProvider)
    case networkError(APIProvider, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p):
            "No API key configured for \(p.displayName)"
        case .invalidAPIKey(let p):
            "Invalid API key for \(p.displayName)"
        case .rateLimited(let p):
            "\(p.displayName) rate limit reached. Try again shortly."
        case .unexpectedResponse(let p):
            "Unexpected response from \(p.displayName)"
        case .networkError(let p, let detail):
            "\(p.displayName) error: \(detail)"
        }
    }
}
