//
//  KeychainService.swift
//  Cera
//
//  Created by Oskar Pajka on 07/03/2026.
//

import Foundation
import Security

/// Thin wrapper around the Security framework for storing and retrieving
/// sensitive strings (API keys) in the system Keychain.
enum KeychainService {

    private static let serviceName = "com.cera.apikeys"

    // MARK: - Public

    /// Saves or updates a value for the given account.
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        // Remove any existing entry first.
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data

        let status = SecItemAdd(item as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieves the stored value for the given account, if any.
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the stored value for the given account.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    /// Returns true if a value exists for the given account.
    static func exists(key: String) -> Bool {
        load(key: key) != nil
    }
}
