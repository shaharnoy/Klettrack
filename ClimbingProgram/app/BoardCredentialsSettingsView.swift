import SwiftUI

struct BoardCredentialsSettingsView: View {
    @State private var activeBoard: TB2Client.Board?
    @State private var credsUsername = ""
    @State private var credsPassword = ""
    @State private var boardCredentialsVersion = 0

    var body: some View {
        List {
            Section {
                LabeledContent("Tension Board", value: boardCredentialStatus(for: .tension))
                HStack(spacing: 12) {
                    Button("Manage") {
                        openCredentialsEditor(for: .tension)
                    }
                    .buttonStyle(.bordered)
                    if hasBoardCredentials(for: .tension) {
                        Button("Clear", role: .destructive) {
                            clearBoardCredentials(for: .tension)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                LabeledContent("Kilter Board", value: boardCredentialStatus(for: .kilter))
                HStack(spacing: 12) {
                    Button("Manage") {
                        openCredentialsEditor(for: .kilter)
                    }
                    .buttonStyle(.bordered)
                    if hasBoardCredentials(for: .kilter) {
                        Button("Clear", role: .destructive) {
                            clearBoardCredentials(for: .kilter)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Board Credentials")
            } footer: {
                Text("Credentials are stored securely in your device keychain.")
            }
            .id(boardCredentialsVersion)
        }
        .navigationTitle("Board Credentials")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeBoard) { board in
            TB2CredentialsSheet(
                header: board == .kilter ? "Kilter login details" : "TB2 login details",
                username: $credsUsername,
                password: $credsPassword,
                onSave: {
                    let username = credsUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let password = credsPassword

                    do {
                        if username.isEmpty && password.isEmpty {
                            try CredentialsStore.deleteBoardCredentials(for: board)
                        } else {
                            try CredentialsStore.saveBoardCredentials(
                                for: board,
                                username: username,
                                password: password
                            )
                        }
                        boardCredentialsVersion += 1
                        activeBoard = nil
                    } catch {
                        activeBoard = nil
                    }
                },
                onCancel: {
                    activeBoard = nil
                }
            )
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
        activeBoard = board
    }

    private func clearBoardCredentials(for board: TB2Client.Board) {
        do {
            try CredentialsStore.deleteBoardCredentials(for: board)
            boardCredentialsVersion += 1
            if activeBoard == board {
                credsUsername = ""
                credsPassword = ""
            }
        } catch {
            print("Failed to delete credentials for \(board): \(error)")
        }
    }

    private func hasBoardCredentials(for board: TB2Client.Board) -> Bool {
        CredentialsStore.loadBoardCredentials(for: board) != nil
    }

    private func boardCredentialStatus(for board: TB2Client.Board) -> String {
        hasBoardCredentials(for: board) ? "Configured" : "Not set"
    }
}
