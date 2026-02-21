//
//  SyncAPIClient.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation

struct SyncAPIConfiguration: Sendable {
    let syncFunctionBaseURL: URL
    let maxRetryAttempts: Int
    let maxRetryDelaySeconds: Double

    init(
        syncFunctionBaseURL: URL,
        maxRetryAttempts: Int = 4,
        maxRetryDelaySeconds: Double = 8
    ) {
        self.syncFunctionBaseURL = syncFunctionBaseURL
        self.maxRetryAttempts = max(1, maxRetryAttempts)
        self.maxRetryDelaySeconds = max(1, maxRetryDelaySeconds)
    }
}

enum SyncAPIError: Error, Sendable, LocalizedError {
    case insecureEndpoint
    case invalidResponse
    case unauthorized
    case forbidden
    case http(statusCode: Int, reason: String?)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .insecureEndpoint:
            return "Sync endpoint must use HTTPS."
        case .invalidResponse:
            return "Sync server returned an invalid response."
        case .unauthorized:
            return "Authentication is required for sync."
        case .forbidden:
            return "This account is not authorized for sync."
        case .http(_, let reason):
            return reason ?? "Sync request failed."
        case .decodingFailed:
            return "Unable to decode sync response."
        }
    }
}

actor SyncAPIClient {
    typealias AccessTokenProvider = @Sendable () async throws -> String
    typealias ForceRefreshTokenProvider = @Sendable () async throws -> String

    private let configuration: SyncAPIConfiguration
    private let session: URLSession
    private let tokenProvider: AccessTokenProvider
    private let forceRefreshTokenProvider: ForceRefreshTokenProvider?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: SyncAPIConfiguration,
        tokenProvider: @escaping AccessTokenProvider,
        forceRefreshTokenProvider: ForceRefreshTokenProvider? = nil,
        session: URLSession? = nil
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.forceRefreshTokenProvider = forceRefreshTokenProvider

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 60
            config.allowsConstrainedNetworkAccess = true
            config.allowsExpensiveNetworkAccess = true
            self.session = URLSession(configuration: config)
        }

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func push(request: SyncPushRequest) async throws -> SyncPushResponse {
        try await postJSON(path: "push", body: request, as: SyncPushResponse.self)
    }

    func pull(request: SyncPullRequest) async throws -> SyncPullResponse {
        try await postJSON(path: "pull", body: request, as: SyncPullResponse.self)
    }

    private func postJSON<T: Decodable, U: Encodable>(path: String, body: U, as _: T.Type) async throws -> T {
        guard configuration.syncFunctionBaseURL.scheme?.localizedLowercase == "https" else {
            throw SyncAPIError.insecureEndpoint
        }

        var token: String? = nil
        var didForceRefreshAfterUnauthorized = false
        var attempt = 0

        while true {
            do {
                try Task.checkCancellation()
                if token == nil {
                    token = try await self.tokenProvider()
                }

                var request = URLRequest(url: self.configuration.syncFunctionBaseURL.appending(path: path))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
                request.httpBody = try self.encoder.encode(body)

                let (data, response) = try await self.session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw SyncAPIError.invalidResponse
                }

                guard 200..<300 ~= httpResponse.statusCode else {
                    let reason = Self.parseErrorReason(from: data)
                    switch httpResponse.statusCode {
                    case 401:
                        if !didForceRefreshAfterUnauthorized, let forceRefreshTokenProvider {
                            token = try await forceRefreshTokenProvider()
                            didForceRefreshAfterUnauthorized = true
                            continue
                        }
                        throw SyncAPIError.unauthorized
                    case 403:
                        throw SyncAPIError.forbidden
                    default:
                        throw SyncAPIError.http(statusCode: httpResponse.statusCode, reason: reason)
                    }
                }

                do {
                    return try self.decoder.decode(T.self, from: data)
                } catch {
                    throw SyncAPIError.decodingFailed
                }
            } catch let cancellationError as CancellationError {
                throw cancellationError
            } catch SyncAPIError.unauthorized {
                throw SyncAPIError.unauthorized
            } catch SyncAPIError.forbidden {
                throw SyncAPIError.forbidden
            } catch {
                attempt += 1
                guard attempt < self.configuration.maxRetryAttempts, self.isRetryable(error) else {
                    throw error
                }
                token = nil
                let baseSeconds = min(pow(2, Double(attempt - 1)), self.configuration.maxRetryDelaySeconds)
                let jitter = Double.random(in: 0..<0.25)
                try await Task.sleep(for: .seconds(baseSeconds + jitter))
            }
        }
    }

    private func isRetryable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        if case SyncAPIError.http(let statusCode, _) = error {
            return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        }

        return false
    }

    private static func parseErrorReason(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errorValue = object["error"] as? String
        else {
            return nil
        }
        return errorValue
    }
}
