//
//  CredentialsStore.swift
//  ClimbingProgram
//

import Foundation
import Security

struct TB2Credentials: Codable {
    let username: String
    let password: String
}

enum CredentialsStore {
    private static let service = "ClimbingProgram.TB2"
    private static let account = "credentials"
    
    // MARK: - Legacy single-credential helpers (kept for compatibility; used for Tension by older code)
    static func loadTB2Credentials() -> TB2Credentials? {
        loadBoardCredentials(for: .tension)
    }

    static func saveTB2Credentials(username: String, password: String) throws {
        try saveBoardCredentials(for: .tension, username: username, password: password)
    }

    static func deleteTB2Credentials() throws {
        try deleteBoardCredentials(for: .tension)
    }
    
    // MARK: - Per-board credentials
    
    private static func account(for board: TB2Client.Board) -> String {
        switch board {
        case .tension: return "\(account).tension"
        case .kilter:  return "\(account).kilter"
        }
    }

    static func loadBoardCredentials(for board: TB2Client.Board) -> TB2Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: board),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(TB2Credentials.self, from: data)
    }

    static func saveBoardCredentials(for board: TB2Client.Board, username: String, password: String) throws {
        let creds = TB2Credentials(username: username, password: password)
        let data = try JSONEncoder().encode(creds)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: board)
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }

        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus), userInfo: [NSLocalizedDescriptionKey: "Keychain add failed (\(addStatus))"])
            }
        } else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain update failed (\(status))"])
        }
    }

    static func deleteBoardCredentials(for board: TB2Client.Board) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: board)
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain delete failed (\(status))"])
        }
    }
}

