//
//  SupabaseSessionStore.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation
import Security

enum SupabaseSessionStoreError: Error, Sendable, LocalizedError {
    case keychainSaveFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
    case invalidStoredSession
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .keychainSaveFailed(let status):
            return "Unable to save auth session (\(status))."
        case .keychainDeleteFailed(let status):
            return "Unable to remove auth session (\(status))."
        case .invalidStoredSession:
            return "Stored auth session is invalid."
        case .missingAccessToken:
            return "No auth session is available."
        }
    }
}

actor SupabaseSessionStore {
    private let service = "ClimbingProgram.SupabaseAuth"
    private let account = "session"

    func loadSession() throws -> SupabaseSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SupabaseSessionStoreError.invalidStoredSession
        }
        return try JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    func saveSession(_ session: SupabaseSession) throws {
        let data = try JSONEncoder().encode(session)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SupabaseSessionStoreError.keychainSaveFailed(addStatus)
            }
            return
        }
        throw SupabaseSessionStoreError.keychainSaveFailed(updateStatus)
    }

    func clearSession() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SupabaseSessionStoreError.keychainDeleteFailed(status)
        }
    }

    func requireAccessToken() throws -> String {
        guard let session = try loadSession(), !session.accessToken.isEmpty else {
            throw SupabaseSessionStoreError.missingAccessToken
        }
        return session.accessToken
    }
}
