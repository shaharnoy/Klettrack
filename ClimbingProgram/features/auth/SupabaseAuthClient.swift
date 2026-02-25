//
//  SupabaseAuthClient.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation

enum SupabaseAuthError: Error, Sendable, LocalizedError {
    enum UnauthorizedReason: Sendable {
        case credentialsInvalid
        case sessionInvalid
        case unknown
    }

    case invalidResponse
    case unauthorized(reason: UnauthorizedReason)
    case transientNetwork
    case transientServer(statusCode: Int)
    case requestFailed(statusCode: Int, reason: String?)
    case signInFailed
    case usernameResolutionFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Supabase auth returned an invalid response."
        case .unauthorized(let reason):
            switch reason {
            case .credentialsInvalid:
                return "Authentication failed. Check your credentials."
            case .sessionInvalid:
                return "Your session has expired. Please sign in again."
            case .unknown:
                return "Authentication failed."
            }
        case .transientNetwork:
            return "Unable to reach authentication service. Check your connection and try again."
        case .transientServer:
            return "Authentication service is temporarily unavailable. Please try again."
        case .requestFailed(_, let reason):
            return reason ?? "Supabase auth request failed."
        case .signInFailed:
            return "Unable to sign in with Supabase Auth."
        case .usernameResolutionFailed:
            return "Unable to resolve username to email."
        }
    }

    var requiresReauthentication: Bool {
        if case .unauthorized(reason: .sessionInvalid) = self {
            return true
        }
        return false
    }

    var isTransient: Bool {
        switch self {
        case .transientNetwork, .transientServer:
            return true
        default:
            return false
        }
    }
}

struct SupabaseAuthUser: Decodable, Sendable {
    let id: String
    let email: String?
}

actor SupabaseAuthClient {
    private enum Endpoint {
        case signIn
        case refresh
        case fetchUser
        case usernameResolver
    }

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

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw mapHTTPError(statusCode: http.statusCode, data: data, endpoint: .signIn)
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

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw mapHTTPError(statusCode: http.statusCode, data: data, endpoint: .refresh)
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

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw mapHTTPError(statusCode: http.statusCode, data: data, endpoint: .fetchUser)
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

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if let http = response as? HTTPURLResponse {
                throw mapHTTPError(statusCode: http.statusCode, data: data, endpoint: .usernameResolver)
            }
            throw SupabaseAuthError.usernameResolutionFailed
        }
        let payload = try JSONDecoder().decode(UsernameResolutionResponse.self, from: data)
        return payload.email
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw SupabaseAuthError.transientNetwork
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                    .networkConnectionLost,
                    .cannotFindHost,
                    .cannotConnectToHost,
                    .dnsLookupFailed,
                    .timedOut,
                    .internationalRoamingOff,
                    .callIsActive,
                    .dataNotAllowed:
                throw SupabaseAuthError.transientNetwork
            default:
                throw SupabaseAuthError.requestFailed(statusCode: 0, reason: urlError.localizedDescription)
            }
        } catch {
            throw SupabaseAuthError.requestFailed(statusCode: 0, reason: error.localizedDescription)
        }
    }

    private func mapHTTPError(statusCode: Int, data: Data, endpoint: Endpoint) -> SupabaseAuthError {
        let payload = decodeErrorPayload(from: data)
        let reasonText = payload?.reasonText
        let normalizedReason = reasonText?.localizedLowercase ?? ""

        if statusCode >= 500 {
            return .transientServer(statusCode: statusCode)
        }

        if endpoint == .signIn && (statusCode == 400 || statusCode == 401 || statusCode == 403) {
            return .unauthorized(reason: .credentialsInvalid)
        }

        if endpoint == .refresh {
            if statusCode == 400 || statusCode == 401 || statusCode == 403 {
                if normalizedReason.localizedStandardContains("refresh token")
                    || normalizedReason.localizedStandardContains("invalid_grant")
                    || normalizedReason.localizedStandardContains("session not found") {
                    return .unauthorized(reason: .sessionInvalid)
                }
                return .unauthorized(reason: .unknown)
            }
        }

        if endpoint == .fetchUser && (statusCode == 401 || statusCode == 403) {
            if normalizedReason.localizedStandardContains("session not found")
                || normalizedReason.localizedStandardContains("jwt expired")
                || normalizedReason.localizedStandardContains("invalid jwt") {
                return .unauthorized(reason: .sessionInvalid)
            }
            return .unauthorized(reason: .unknown)
        }

        if statusCode == 429 {
            return .transientServer(statusCode: statusCode)
        }

        if endpoint == .usernameResolver {
            return .usernameResolutionFailed
        }

        if endpoint == .signIn {
            return .signInFailed
        }

        return .requestFailed(statusCode: statusCode, reason: reasonText)
    }

    private func decodeErrorPayload(from data: Data) -> AuthErrorPayload? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(AuthErrorPayload.self, from: data)
    }
}

private struct UsernameResolutionResponse: Decodable {
    let email: String
}

private struct AuthErrorPayload: Decodable {
    let error: String?
    let errorDescription: String?
    let code: String?
    let message: String?
    let msg: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case code
        case message
        case msg
    }

    var reasonText: String? {
        firstNonEmpty([
            errorDescription,
            message,
            msg,
            error,
            code
        ])
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                continue
            }
            return trimmed
        }
        return nil
    }
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
