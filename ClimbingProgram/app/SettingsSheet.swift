//
//  SettingSheet.swift
//  Klettrack
//  Created by Shahar Noy on 12.10.25.
//

import SwiftUI
import SwiftData

struct SettingsSheet: View {
    private enum SheetRoute: String, Identifiable {
        case about
        case contribute
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(TimerAppState.self) private var timerAppState
    @Environment(\.modelContext) private var context
    @State private var activeBoard: TB2Client.Board? = nil
    @State private var credsUsername: String = ""
    @State private var credsPassword: String = ""
    @State private var isEditingCredentials = true
    @State private var sheetRoute: SheetRoute?
    
    // Export state
    @State private var showExporter = false
    @State private var exportDoc: LogCSVDocument? = nil
    @State private var hasRequestedReviewThisSession = false
    
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
                    NavigationLink {
                        FeatureFlagsView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "switch.2")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Feature Flags")
                                    .font(.body)
                                Text("Enable or disable experimental behavior")
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
                                Text("Gallery")
                                    .font(.body)
                                Text("Browse all climbs photos and videos")
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
                                Text("Export your climbs and sessions")
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
                    //rate the app
                    Button {
                        if !hasRequestedReviewThisSession {
                            if let url = URL(string: "itms-apps://apps.apple.com/app/id6754015176?action=write-review") {
                                UIApplication.shared.open(url)
                                hasRequestedReviewThisSession = true
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .imageScale(.medium)
                            Text("Rate klettrack")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
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
                        sheetRoute = .contribute
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
                        sheetRoute = .about
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
        .sheet(item: $activeBoard) { board in
            TB2CredentialsSheet(
                header: (board == .kilter) ? "Kilter login details" : "TB2 login details",
                username: $credsUsername,
                password: $credsPassword,
                onSave: {
                    let username = credsUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let password = credsPassword
                    
                    do {
                        if username.isEmpty && password.isEmpty {
                            // Both empty → treat as "remove credentials"
                            try CredentialsStore.deleteBoardCredentials(for: board)
                        } else {
                            // Non-empty → save/update credentials
                            try CredentialsStore.saveBoardCredentials(
                                for: board,
                                username: username,
                                password: password
                            )
                        }
                        
                        isEditingCredentials = false
                        activeBoard = nil
                    } catch {
                        isEditingCredentials = false
                        activeBoard = nil
                    }
                },
                onCancel: {
                    isEditingCredentials = false
                    activeBoard = nil
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
        // About / Contribute sheet
        .sheet(item: $sheetRoute) { route in
            NavigationStack {
                Group {
                    switch route {
                    case .about:
                        AboutView.klettrack
                    case .contribute:
                        AboutView.contribute
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { sheetRoute = nil }
                    }
                }
            }
        }
    }

    private func openCredentialsEditor(for board: TB2Client.Board) {
        if let creds = CredentialsStore.loadBoardCredentials(for: board) {
            credsUsername = creds.username
            credsPassword = creds.password
        } else {
            credsUsername = ""
            credsPassword = ""
        }
        isEditingCredentials = true
        activeBoard = board
    }
    
    private func clearBoardCredentials(for board: TB2Client.Board) {
        do {
            try CredentialsStore.deleteBoardCredentials(for: board)
            
            if activeBoard == board {
                credsUsername = ""
                credsPassword = ""
            }
        } catch {
            print("Failed to delete credentials for \(board): \(error)")
        }
    }

}
