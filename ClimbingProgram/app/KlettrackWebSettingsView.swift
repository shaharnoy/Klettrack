//
//  KlettrackWebSettingsView.swift
//  Klettrack
//  Created by Shahar Noy on 14.02.26.
//

import SwiftUI

struct KlettrackWebSettingsView: View {
    @State private var supabaseIdentifier = ""
    @State private var supabasePassword = ""
    @State private var authManager = AuthManager.shared

    var body: some View {
        List {
            Section {
                switch authManager.state {
                case .unconfigured:
                    Text("Supabase config missing. Set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .restoring:
                    Text("Restoring session...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .signingIn:
                    Text("Signing in...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .signedIn(let email):
                    Text("Signed in as \(email ?? "user")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .signedOut:
                    Text("Signed out")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if authManager.isSignedIn {
                    Text(syncStatusText(authManager.syncState))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(lastSyncText(authManager.lastSyncAt))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Sync Now") {
                        Task {
                            await authManager.triggerSyncNow()
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if !authManager.isSignedIn {
                    TextField("Email or username", text: $supabaseIdentifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $supabasePassword)
                    Button("Sign In") {
                        Task {
                            _ = await authManager.signIn(
                                identifier: supabaseIdentifier,
                                password: supabasePassword
                            )
                            supabasePassword = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        supabaseIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || supabasePassword.isEmpty
                    )
                } else {
                    Button("Sign Out") {
                        Task {
                            await authManager.signOut()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Cloud Sync")
            }

            if authManager.isSignedIn, !authManager.syncConflicts.isEmpty {
                Section("Conflict Center") {
                    SyncConflictCenterView(
                        conflicts: authManager.syncConflicts,
                        onResolveKeepMine: { conflict in
                            _ = await authManager.resolveSyncConflictKeepMine(conflict)
                        },
                        onResolveKeepServer: { conflict in
                            _ = await authManager.resolveSyncConflictKeepServer(conflict)
                        },
                        onResolveAllKeepMine: {
                            await authManager.resolveAllSyncConflictsKeepMine()
                        },
                        onResolveAllKeepServer: {
                            await authManager.resolveAllSyncConflictsKeepServer()
                        }
                    )
                }
            }

            Section {
                Text("Use klettrack web for easier training plan setup and sync your logged data")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let websiteURL = URL(string: "https://klettrack.com/app.html#/login") {
                    Link("klettrack web", destination: websiteURL)
                        .font(.footnote.weight(.semibold))
                }
                if let registerURL = URL(string: "https://klettrack.com/app.html#/register") {
                    Link("New user? Register here!", destination: registerURL)
                        .font(.footnote.weight(.semibold))
                }
            } header: {
                Text("klettrack web")
            }
        }
        .navigationTitle("klettrack web")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func syncStatusText(_ state: SyncManager.State) -> String {
        switch state {
        case .idle:
            return "Sync status: idle"
        case .syncing:
            return "Sync status: syncing"
        case .conflict(let count):
            return "Sync status: \(count) conflict\(count == 1 ? "" : "s")"
        case .failed(let message):
            return "Sync status: failed (\(message))"
        }
    }

    private func lastSyncText(_ lastSyncAt: Date?) -> String {
        guard let lastSyncAt else {
            return "Last sync: not yet"
        }
        return "Last sync: \(lastSyncAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
