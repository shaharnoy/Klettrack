//
//  SettingSheet.swift
//  Klettrack
//  Created by Shahar Noy on 12.10.25.
//

import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var timerAppState: TimerAppState
    @State private var showingCredentialsSheet = true
    @State private var credsUsername: String = ""
    @State private var credsPassword: String = ""
    @State private var isEditingCredentials = true
    @State private var pendingBoard: TB2Client.Board? = nil
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CatalogView()
                    } label: {
                        Label("Exercise Catalog", systemImage: "square.grid.2x2")
                    }
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
                            Label("Boards Credentials Manager", systemImage: "lock.circle")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    
                    .buttonStyle(.plain)
                    NavigationLink {
                        AboutView.klettrack
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Spacer()
                        Text("Made with ❤️ in Berlin.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(false)
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
