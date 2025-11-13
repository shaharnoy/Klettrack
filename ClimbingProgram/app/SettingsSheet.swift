//
//  SettingSheet.swift
//  Klettrack
//  Created by Shahar Noy on 12.10.25.
//

import SwiftUI
import SwiftData

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var timerAppState: TimerAppState
    @Environment(\.modelContext) private var context
    @State private var showingCredentialsSheet = false
    @State private var credsUsername: String = ""
    @State private var credsPassword: String = ""
    @State private var isEditingCredentials = true
    @State private var pendingBoard: TB2Client.Board? = nil
    @State private var showingAbout = false
    @State private var showingContribute = false
    
    // Export state
    @State private var showExporter = false
    @State private var exportDoc: LogCSVDocument? = nil
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CatalogView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "square.grid.2x2")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Exercise Catalog")
                                    .font(.body)
                                Text("Your climbing and training exercises")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    
                    NavigationLink {
                        TimerTemplatesListView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "timer")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Timer Templates")
                                    .font(.body)
                                Text("Create or customize timer templates")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    
                    //metadata manager
                    NavigationLink {
                        ClimbMetaManagerView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Data Manager")
                                    .font(.body)
                                Text("Edit day types, styles, and gyms")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    //Media Manager
                    NavigationLink {
                        MediaManagerView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "photo.stack")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Media Manager")
                                    .font(.body)
                                Text("Browse all climbs photos and videos")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 1)
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
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "lock.circle")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Board Connections")
                                        .font(.body)
                                    Text("Add or update your boards credentials")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 1)
                    }
                    .buttonStyle(.plain)
                    
                    // Export CSV button (trigger export without navigation)
                    Button {
                        exportDoc = LogCSV.makeExportCSV(context: context)
                        showExporter = true
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Export Logs")
                                    .font(.body)
                                Text("Save your climbs and sessions as a CSV file")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
                
                // About section (subtle separation)
                Section {
                    //Feature request / feedback button opens link to roadmap
                    Button {
                        if let url = URL(string: "https://klettrack.featurebase.app/") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "megaphone")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Got an idea? See what’s planned next")
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .buttonStyle(.plain)
                    // Contribute button opens AboutView.contribute
                    Button {
                        showingContribute = true
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: "lightbulb")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Why is klettrack free?")
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .buttonStyle(.plain)
                    
                    //About button opens AboutView.klettrack
                    Button {
                        showingAbout = true
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "info.circle")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("About")
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .buttonStyle(.plain)
                    
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
        // Exporter
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: .commaSeparatedText,
            defaultFilename: "klettrack-log-\(Date().formatted(.dateTime.year().month().day()))"
        ) { result in
            switch result {
            case .success:
                break
            case .failure:
                break
            }
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
        // Contribute sheet
        .sheet(isPresented: $showingContribute) {
            NavigationStack {
                AboutView.contribute
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingContribute = false }
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
