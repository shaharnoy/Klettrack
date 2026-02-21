import SwiftUI

private enum SyncBulkResolutionChoice: String, CaseIterable, Identifiable {
    case keepMine
    case keepServer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keepMine:
            return "Keep Mine"
        case .keepServer:
            return "Keep Server"
        }
    }
}

struct SyncConflictCenterView: View {
    let conflicts: [SyncPushConflict]
    let onResolveKeepMine: @MainActor (SyncPushConflict) async -> Void
    let onResolveKeepServer: @MainActor (SyncPushConflict) async -> Void
    let onResolveAllKeepMine: @MainActor () async -> Int
    let onResolveAllKeepServer: @MainActor () async -> Int

    @State private var bulkChoice: SyncBulkResolutionChoice = .keepServer
    @State private var isApplyingAll = false
    @State private var bulkActionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review each conflict and choose whether to keep your local change or the server version.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Apply to all", selection: $bulkChoice) {
                Text("Keep Mine").tag(SyncBulkResolutionChoice.keepMine)
                Text("Keep Server").tag(SyncBulkResolutionChoice.keepServer)
            }
            .pickerStyle(.segmented)
            .disabled(isApplyingAll)

            Button(isApplyingAll ? "Applying..." : "Apply to All Conflicts") {
                Task {
                    await applyBulkSelection()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isApplyingAll || conflicts.isEmpty)

            if let bulkActionMessage {
                Text(bulkActionMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(conflicts, id: \.opId) { conflict in
                SyncConflictCard(
                    conflict: conflict,
                    isDisabled: isApplyingAll,
                    onResolveKeepMine: onResolveKeepMine,
                    onResolveKeepServer: onResolveKeepServer
                )
            }
        }
    }

    @MainActor
    private func applyBulkSelection() async {
        isApplyingAll = true
        defer { isApplyingAll = false }

        let resolvedCount: Int
        switch bulkChoice {
        case .keepMine:
            resolvedCount = await onResolveAllKeepMine()
        case .keepServer:
            resolvedCount = await onResolveAllKeepServer()
        }
        bulkActionMessage = "Applied to \(resolvedCount) conflict\(resolvedCount == 1 ? "" : "s")."
    }
}

private struct SyncConflictCard: View {
    let conflict: SyncPushConflict
    let isDisabled: Bool
    let onResolveKeepMine: @MainActor (SyncPushConflict) async -> Void
    let onResolveKeepServer: @MainActor (SyncPushConflict) async -> Void

    @State private var isResolving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(conflict.displayEntityLabel) · \(conflict.displayEntityIdentifier)")
                .font(.footnote.weight(.semibold))
                .textSelection(.enabled)

            Text(conflict.displayReason)
                .font(.footnote)
                .foregroundStyle(.secondary)

            DisclosureGroup("Review server version (\(conflict.displayServerVersion))") {
                if conflict.serverPreviewRows.isEmpty {
                    Text("No server snapshot available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(conflict.serverPreviewRows, id: \.key) { row in
                            Text("\(row.key): \(row.value)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .font(.footnote)

            HStack(spacing: 8) {
                Button("Keep Mine") {
                    Task {
                        await resolveKeepMine()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled || isResolving)

                Button("Keep Server") {
                    Task {
                        await resolveKeepServer()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isDisabled || isResolving)
            }
        }
        .padding(.vertical, 4)
    }

    @MainActor
    private func resolveKeepMine() async {
        isResolving = true
        defer { isResolving = false }
        await onResolveKeepMine(conflict)
    }

    @MainActor
    private func resolveKeepServer() async {
        isResolving = true
        defer { isResolving = false }
        await onResolveKeepServer(conflict)
    }
}
