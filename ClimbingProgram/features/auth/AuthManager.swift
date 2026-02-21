//
//  AuthManager.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AuthManager {
    enum State: Equatable {
        case unconfigured
        case signedOut
        case restoring
        case signingIn
        case signedIn(email: String?)
        case failed(String)
    }

    static let shared = AuthManager()

    private(set) var state: State = .unconfigured
    private(set) var userID: String?

    private var authClient: SupabaseAuthClient?
    private var sessionStore: SupabaseSessionStore?
    private var syncStore: SyncStoreActor?
    private var syncManager: SyncManager?
    private let foregroundSyncDebouncer = SyncDebouncer()
    private let syncTokenRefreshLeadTime: TimeInterval = 120

    private init() {}

    var isConfigured: Bool {
        authClient != nil && sessionStore != nil && syncStore != nil && syncManager != nil
    }

    var isSignedIn: Bool {
        if case .signedIn = state {
            return true
        }
        return false
    }

    var syncState: SyncManager.State {
        syncManager?.state ?? .idle
    }

    var syncConflicts: [SyncPushConflict] {
        syncManager?.conflicts ?? []
    }

    var syncTelemetryEvents: [SyncConflictTelemetryEvent] {
        syncManager?.telemetryEvents ?? []
    }

    var lastSyncAt: Date? {
        syncManager?.lastSyncAt
    }

    var isSyncAvailable: Bool {
        isConfigured
    }

    func configureIfNeeded(modelContainer: ModelContainer) {
        guard !isConfigured else { return }
        guard let configuration = SupabaseAuthConfiguration.load() else {
            state = .unconfigured
            return
        }

        let store = SupabaseSessionStore()
        let syncStore = SyncStoreActor(modelContainer: modelContainer)
        let syncAPIClient = SyncAPIClient(
            configuration: SyncAPIConfiguration(syncFunctionBaseURL: configuration.syncFunctionBaseURL),
            tokenProvider: { [weak self] in
                guard let self else { throw SupabaseSessionStoreError.missingAccessToken }
                return try await self.accessTokenForSync(forceRefresh: false)
            },
            forceRefreshTokenProvider: { [weak self] in
                guard let self else { throw SupabaseSessionStoreError.missingAccessToken }
                return try await self.accessTokenForSync(forceRefresh: true)
            }
        )
        let syncManager = SyncManager(apiClient: syncAPIClient, store: syncStore)

        self.authClient = SupabaseAuthClient(configuration: configuration)
        self.sessionStore = store
        self.syncStore = syncStore
        self.syncManager = syncManager
        self.state = .signedOut
    }

    func restoreSession() async {
        guard let sessionStore, let authClient, let syncManager, let syncStore else {
            state = .unconfigured
            return
        }

        state = .restoring

        do {
            guard var session = try await sessionStore.loadSession() else {
                try await syncStore.prepareForSignedOutState(clearPendingMutations: true)
                await syncManager.setSyncEnabled(false, userId: nil)
                state = .signedOut
                userID = nil
                return
            }

            if session.expiresAt <= Date.now.addingTimeInterval(60) {
                session = try await authClient.refreshSession(refreshToken: session.refreshToken)
                try await sessionStore.saveSession(session)
            } else {
                _ = try await authClient.fetchUser(accessToken: session.accessToken)
            }

            userID = session.userID
            state = .signedIn(email: session.email)
            await syncManager.setSyncEnabled(isSyncAvailable, userId: session.userID)
        } catch {
            try? await sessionStore.clearSession()
            try? await syncStore.prepareForSignedOutState(clearPendingMutations: true)
            await syncManager.setSyncEnabled(false, userId: nil)
            userID = nil
            state = .signedOut
        }
    }

    @discardableResult
    func signIn(identifier: String, password: String) async -> Bool {
        guard let sessionStore, let authClient, let syncManager else {
            state = .unconfigured
            return false
        }

        state = .signingIn

        do {
            let session = try await authClient.signInWithPassword(identifier: identifier, password: password)
            try await sessionStore.saveSession(session)
            userID = session.userID
            state = .signedIn(email: session.email)
            await syncManager.setSyncEnabled(isSyncAvailable, userId: session.userID)
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    func signOut() async {
        guard let sessionStore, let syncStore, let syncManager else {
            state = .unconfigured
            return
        }

        if let authClient, let accessToken = try? await sessionStore.requireAccessToken() {
            await authClient.signOut(accessToken: accessToken)
        }

        try? await sessionStore.clearSession()
        try? await syncStore.prepareForSignedOutState(clearPendingMutations: true)
        await syncManager.setSyncEnabled(false, userId: nil)
        userID = nil
        state = .signedOut
    }

    @discardableResult
    func resolveSyncConflictKeepMine(_ conflict: SyncPushConflict) async -> Bool {
        guard let syncManager else { return false }
        return await syncManager.resolveConflictKeepMine(conflict)
    }

    @discardableResult
    func resolveSyncConflictKeepServer(_ conflict: SyncPushConflict) async -> Bool {
        guard let syncManager else { return false }
        return await syncManager.resolveConflictKeepServer(conflict)
    }

    @discardableResult
    func resolveAllSyncConflictsKeepMine() async -> Int {
        guard let syncManager else { return 0 }
        return await syncManager.resolveAllConflictsKeepMine()
    }

    @discardableResult
    func resolveAllSyncConflictsKeepServer() async -> Int {
        guard let syncManager else { return 0 }
        return await syncManager.resolveAllConflictsKeepServer()
    }

    func triggerSyncNow() async {
        guard isSyncAvailable else { return }
        await syncManager?.runSyncNow(reason: "manual")
    }

    func handleAppDidBecomeActive() async {
        guard isSyncAvailable else { return }
        guard isSignedIn else { return }
        await foregroundSyncDebouncer.schedule(after: .seconds(1)) { [weak self] in
            await self?.syncManager?.runSyncNow(reason: "foreground_active")
        }
    }

    func handleBackgroundRefreshTask() async {
        guard isSyncAvailable else { return }
        guard isSignedIn else { return }
        await syncManager?.runSyncNow(reason: "background_refresh")
    }

    private func accessTokenForSync(forceRefresh: Bool) async throws -> String {
        guard let sessionStore else {
            throw SupabaseSessionStoreError.missingAccessToken
        }

        guard var session = try await sessionStore.loadSession() else {
            throw SupabaseSessionStoreError.missingAccessToken
        }

        let requiresRefresh = forceRefresh || session.expiresAt <= Date.now.addingTimeInterval(syncTokenRefreshLeadTime)
        if requiresRefresh {
            guard let authClient else {
                throw SupabaseSessionStoreError.missingAccessToken
            }
            session = try await authClient.refreshSession(refreshToken: session.refreshToken)
            try await sessionStore.saveSession(session)
            userID = session.userID
        }

        guard !session.accessToken.isEmpty else {
            throw SupabaseSessionStoreError.missingAccessToken
        }
        return session.accessToken
    }
}
