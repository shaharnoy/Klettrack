//
//  SettingSheet.swift
//  Klettrack
//  Created by Shahar Noy on 12.10.25.
//

import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var timerAppState: TimerAppState
    @State private var showingCredentialsSheet = false
    @State private var credsUsername: String = ""
    @State private var credsPassword: String = ""
    @State private var isEditingCredentials = true
    @State private var pendingBoard: TB2Client.Board? = nil
    @State private var showingAbout = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CatalogView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "square.grid.2x2")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Exercise Catalog")
                                    .font(.body)
                                Text("Add or modify all exercises and climbing drills")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    NavigationLink {
                        TimerTemplatesListView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "timer")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Timer Templates")
                                    .font(.body)
                                Text("Create and edit timer templates")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // NEW: Styles & Gyms manager
                    NavigationLink {
                        ClimbMetaManagerView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Styles & Gyms")
                                    .font(.body)
                                Text("Manage climbing styles and gyms")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Boards credentials menu
                    Menu {
                        Button("TB2 Login") {
                            openCredentialsEditor(for: .tension)
                        }
                        Divider()
                        Button("Kilter Login") {
                            openCredentialsEditor(for: .kilter)
                        }
                    } label: {
                        HStack {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: "lock.circle")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Boards Credentials Manager")
                                        .font(.body)
                                    Text("Store and edit system board credentials.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showingAbout = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                            Text("About")
                                .fixedSize() // avoid truncation
                        }
                        .padding(.horizontal, 35)
                        .padding(.vertical, 2)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)           // or .buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
            }
            .safeAreaInset(edge: .bottom, alignment: .center, spacing: 0) {
                Text("Made with ❤️ in Berlin")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom, alignment: .center, spacing: 0) {
                Text("©Klettrack")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
            
        }
        // Credentials prompt sheet (shared view)
        .sheet(isPresented: $showingCredentialsSheet) {
            TB2CredentialsSheet(
                header: (pendingBoard == .kilter) ? "Kilter login details" : "TB2 login details",
                username: $credsUsername,
                password: $credsPassword,
                onSave: {
                    let username = credsUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let password = credsPassword
                    guard !username.isEmpty, !password.isEmpty, let board = pendingBoard else { return }
                    do {
                        try CredentialsStore.saveBoardCredentials(for: board, username: username, password: password)
                        // In Settings, we just save and close (no auto-sync here)
                        isEditingCredentials = false
                        pendingBoard = nil
                        showingCredentialsSheet = false
                    } catch {
                        // Optional: add an alert if needed
                        isEditingCredentials = false
                        pendingBoard = nil
                        showingCredentialsSheet = false
                    }
                },
                onCancel: {
                    isEditingCredentials = false
                    pendingBoard = nil
                    showingCredentialsSheet = false
                }
            )
        }
        // About sheet
        .sheet(isPresented: $showingAbout) {
            NavigationStack {
                AboutView.klettrack
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingAbout = false }
                        }
                    }
            }
        }
    }

    private func openCredentialsEditor(for board: TB2Client.Board) {
        // Prefill if saved for that board
        if let creds = CredentialsStore.loadBoardCredentials(for: board) {
            credsUsername = creds.username
            credsPassword = creds.password
        } else {
            credsUsername = ""
            credsPassword = ""
        }
        pendingBoard = board
        isEditingCredentials = true
        showingCredentialsSheet = true
    }
}
