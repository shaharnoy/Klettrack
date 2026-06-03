//
//  KilterClient.swift
//  Klettrack
//

import Foundation

struct KilterTokenResponse: Decodable, Sendable {
    let accessToken: String
    let expiresIn: Int?
    let refreshToken: String?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
    }
}

struct KilterLog: Decodable, Sendable {
    let logUuid: String
    let climbUuid: String
    let userUuid: String?
    let gymUuid: String?
    let wallUuid: String?
    let productLayoutUuid: String?
    let angle: Int?
    let flashed: Bool
    let topped: Bool
    let attempts: Int
    let createdAt: String
    let climbName: String?
    let currentDifficultyId: Int?
    let climbRating: KilterClimbRating?
}

struct KilterClimbRating: Decodable, Sendable {
    let climbRatingUuid: String?
    let userUuid: String?
    let gymUuid: String?
    let wallUuid: String?
    let productLayoutUuid: String?
    let climbUuid: String?
    let angle: Int?
    let rating: Int?
    let weight: Double?
    let difficultyGradeId: Int?
    let comment: String?
    let createdAt: String?
    let status: String?
}

struct KilterClient: Sendable {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let tokenURL: URL
    private let apiBaseURL: URL
    private let dataLoader: DataLoader

    init(
        tokenURL: URL = URL(string: "https://idp.kiltergrips.com/realms/kilter/protocol/openid-connect/token")!,
        apiBaseURL: URL = URL(string: "https://portal.kiltergrips.com/api")!,
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.tokenURL = tokenURL
        self.apiBaseURL = apiBaseURL
        self.dataLoader = dataLoader
    }

    func login(username: String, password: String) async throws -> KilterTokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formURLEncoded([
            ("grant_type", "password"),
            ("client_id", "kilter"),
            ("scope", "openid offline_access profile email"),
            ("username", username),
            ("password", password)
        ]).data(using: .utf8)

        let (data, response) = try await dataLoader(request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 400 || http.statusCode == 401 {
            throw NSError(domain: "Kilter", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Invalid Kilter username or password."
            ])
        }

        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Kilter", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Kilter login failed (\(http.statusCode))."
            ])
        }

        return try JSONDecoder().decode(KilterTokenResponse.self, from: data)
    }

    func fetchLogs(accessToken: String) async throws -> [KilterLog] {
        let logsURL = apiBaseURL.appending(path: "logs/")
        var request = URLRequest(url: logsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataLoader(request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 401 {
            throw NSError(domain: "Kilter", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Kilter token expired or unauthorized."
            ])
        }

        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Kilter", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Kilter logs sync failed (\(http.statusCode))."
            ])
        }

        return try JSONDecoder().decode([KilterLog].self, from: data)
    }

    static func formURLEncoded(_ pairs: [(String, String)]) -> String {
        pairs
            .map { key, value in
                "\(formEncode(key))=\(formEncode(value))"
            }
            .joined(separator: "&")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacing("%20", with: "+") ?? value
    }
}
