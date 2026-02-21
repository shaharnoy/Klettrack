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
    @State private var showSignOutConfirmation = false

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
                }

                if !authManager.isSignedIn {
                    TextField("Email or username", text: $supabaseIdentifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    SecureField("Password", text: $supabasePassword)
                        .textContentType(.password)
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
                VStack(alignment: .leading, spacing: 14) {
                    Text("Klettrack Web")
                        .font(.title3.weight(.semibold))
                    Text("Plan sessions faster on the web and keep your climbing logs synced across devices.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if let websiteURL = URL(string: "https://klettrack.com/app.html#/login") {
                        Link("Open Klettrack Web", destination: websiteURL)
                            .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.borderedProminent)
                    }
                    if let registerURL = URL(string: "https://klettrack.com/app.html#/register") {
                        Link("Create New Account", destination: registerURL)
                            .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("klettrack web")
            }
        }
        .navigationTitle("klettrack web")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if authManager.isSignedIn {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await authManager.triggerSyncNow()
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityLabel("Sync now")

                    Button(role: .destructive) {
                        showSignOutConfirmation = true
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityLabel("Sign out")
                }
            }
        }
        .alert("Sign out?", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                Task {
                    await authManager.signOut()
                }
            }
        } message: {
            Text("You’ll need to sign in again to sync with Klettrack Web.")
        }
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
