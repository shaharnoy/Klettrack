import SwiftUI

struct BoardCredentialsSettingsView: View {
    @State private var activeBoard: BoardConnection?
    @State private var credsUsername = ""
    @State private var credsPassword = ""
    @State private var boardCredentialsVersion = 0
    @State private var errorMessage: String?

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
                header: board.credentialsHeader,
                username: $credsUsername,
                password: $credsPassword,
                onSave: {
                    let username = credsUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let password = credsPassword

                    do {
                        if username.isEmpty && password.isEmpty {
                            try deleteCredentials(for: board)
                        } else {
                            try saveCredentials(for: board, username: username, password: password)
                        }
                        boardCredentialsVersion += 1
                        activeBoard = nil
                    } catch {
                        errorMessage = "Unable to save \(boardDisplayName(board)) credentials: \(error.localizedDescription)"
                    }
                },
                onCancel: {
                    activeBoard = nil
                }
            )
        }
        .alert("Credential Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func openCredentialsEditor(for board: BoardConnection) {
        if let creds = loadCredentials(for: board) {
            credsUsername = creds.username
            credsPassword = creds.password
        } else {
            credsUsername = ""
            credsPassword = ""
        }
        activeBoard = board
    }

    private func clearBoardCredentials(for board: BoardConnection) {
        do {
            try deleteCredentials(for: board)
            boardCredentialsVersion += 1
            if activeBoard == board {
                credsUsername = ""
                credsPassword = ""
            }
        } catch {
            errorMessage = "Unable to clear \(boardDisplayName(board)) credentials: \(error.localizedDescription)"
        }
    }

    private func hasBoardCredentials(for board: BoardConnection) -> Bool {
        loadCredentials(for: board) != nil
    }

    private func boardCredentialStatus(for board: BoardConnection) -> String {
        hasBoardCredentials(for: board) ? "Configured" : "Not set"
    }

    private func boardDisplayName(_ board: BoardConnection) -> String {
        board.displayName
    }

    private func loadCredentials(for board: BoardConnection) -> TB2Credentials? {
        switch board {
        case .tension:
            return CredentialsStore.loadBoardCredentials(for: .tension)
        case .kilter:
            return CredentialsStore.loadKilterCredentials().map {
                TB2Credentials(username: $0.username, password: $0.password)
            }
        }
    }

    private func saveCredentials(for board: BoardConnection, username: String, password: String) throws {
        switch board {
        case .tension:
            try CredentialsStore.saveBoardCredentials(for: .tension, username: username, password: password)
        case .kilter:
            try CredentialsStore.saveKilterCredentials(username: username, password: password)
        }
    }

    private func deleteCredentials(for board: BoardConnection) throws {
        switch board {
        case .tension:
            try CredentialsStore.deleteBoardCredentials(for: .tension)
        case .kilter:
            try CredentialsStore.deleteKilterCredentials()
        }
    }
}
