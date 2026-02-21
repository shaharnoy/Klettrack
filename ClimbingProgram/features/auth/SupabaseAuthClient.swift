//
//  SupabaseAuthClient.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation

enum SupabaseAuthError: Error, Sendable, LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case unauthorized
    case signInFailed
    case usernameResolutionFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Supabase auth configuration is missing."
        case .invalidResponse:
            return "Supabase auth returned an invalid response."
        case .unauthorized:
            return "Authentication failed. Check your credentials."
        case .signInFailed:
            return "Unable to sign in with Supabase Auth."
        case .usernameResolutionFailed:
            return "Unable to resolve username to email."
        }
    }
}

struct SupabaseAuthUser: Decodable, Sendable {
    let id: String
    let email: String?
}

actor SupabaseAuthClient {
    private let configuration: SupabaseAuthConfiguration
    private let session: URLSession

    init(configuration: SupabaseAuthConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config)
        }
    }

    func signInWithPassword(identifier: String, password: String) async throws -> SupabaseSession {
        let email = try await resolveEmail(from: identifier)
        let url = configuration.projectURL
            .appending(path: "auth")
            .appending(path: "v1")
            .appending(path: "token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")

        let payload = [
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        if http.statusCode == 400 || http.statusCode == 401 {
            throw SupabaseAuthError.unauthorized
        }
        guard 200..<300 ~= http.statusCode else {
            throw SupabaseAuthError.signInFailed
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return decoded.asSession
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        let url = configuration.projectURL
            .appending(path: "auth")
            .appending(path: "v1")
            .appending(path: "token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw SupabaseAuthError.unauthorized
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return decoded.asSession
    }

    func fetchUser(accessToken: String) async throws -> SupabaseAuthUser {
        let url = configuration.projectURL
            .appending(path: "auth")
            .appending(path: "v1")
            .appending(path: "user")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw SupabaseAuthError.unauthorized
        }

        return try JSONDecoder().decode(SupabaseAuthUser.self, from: data)
    }

    func signOut(accessToken: String) async {
        let url = configuration.projectURL
            .appending(path: "auth")
            .appending(path: "v1")
            .appending(path: "logout")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    private func resolveEmail(from identifier: String) async throws -> String {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.localizedStandardContains("@") {
            return normalized
        }

        guard let resolverURL = configuration.usernameResolverURL else {
            throw SupabaseAuthError.usernameResolutionFailed
        }

        var components = URLComponents(url: resolverURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "username", value: normalized))
        components?.queryItems = queryItems

        guard let resolvedURL = components?.url else {
            throw SupabaseAuthError.usernameResolutionFailed
        }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw SupabaseAuthError.usernameResolutionFailed
        }
        let payload = try JSONDecoder().decode(UsernameResolutionResponse.self, from: data)
        return payload.email
    }
}

private struct UsernameResolutionResponse: Decodable {
    let email: String
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let user: SupabaseAuthUser

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case user
    }

    var asSession: SupabaseSession {
        SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresAt: Date.now.addingTimeInterval(TimeInterval(max(1, expiresIn))),
            userID: user.id,
            email: user.email
        )
    }
}
