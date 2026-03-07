//
//  APIProvider.swift
//  Cera
//
//  Created by Oskar Pajka on 07/03/2026.
//

import Foundation

// MARK: - API Provider

/// Cloud translation providers supported by Cera.
enum APIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI  = "openai"
    case claude  = "claude"
    case gemini  = "gemini"
    case deepL   = "deepl"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .claude:  "Claude"
        case .gemini:  "Gemini"
        case .deepL:   "DeepL"
        }
    }

    /// Identifier used as the Keychain account name for this provider's API key.
    var keychainKey: String {
        "apikey.\(rawValue)"
    }

    /// Whether a key is currently stored in the Keychain.
    var hasStoredKey: Bool {
        KeychainService.exists(key: keychainKey)
    }
}

// MARK: - Translation Mode

/// Controls whether Cera translates locally or via a cloud API.
enum TranslationMode: Equatable, Sendable {
    case local
    case cloud(APIProvider)

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    var provider: APIProvider? {
        if case .cloud(let p) = self { return p }
        return nil
    }

    // MARK: - Persistence

    private static let modeKey     = "translationMode"
    private static let providerKey = "translationProvider"

    func save() {
        switch self {
        case .local:
            UserDefaults.standard.set("local", forKey: Self.modeKey)
            UserDefaults.standard.removeObject(forKey: Self.providerKey)
        case .cloud(let provider):
            UserDefaults.standard.set("cloud", forKey: Self.modeKey)
            UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
        }
    }

    static func load() -> TranslationMode {
        let mode = UserDefaults.standard.string(forKey: modeKey) ?? "local"
        guard mode == "cloud",
              let raw = UserDefaults.standard.string(forKey: providerKey),
              let provider = APIProvider(rawValue: raw) else {
            return .local
        }
        return .cloud(provider)
    }
}
