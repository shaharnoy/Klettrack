import SwiftUI
import SwiftData

struct PendingPlanImport: Identifiable {
    let id = UUID()
    let exchange: PlanCSVExchange.ParsedExchange
    let mode: PlanCSVExchange.ImportMode

    var targetDescription: String {
        switch mode {
        case .newPlan: return "Create a new plan"
        case .existing(let plan): return "Update \(plan.name)"
        }
    }
}

struct PlanImportPreviewSheet: View {
    let pending: PendingPlanImport
    let onComplete: (Result<PlanCSVExchange.Summary, Error>) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var isApplying = false
    @State private var overwriteDayContext = false

    private var importPreview: PlanCSVExchange.ImportPreview {
        PlanCSVExchange.preview(
            pending.exchange,
            mode: pending.mode,
            overwriteDayContext: overwriteDayContext,
            in: context
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                PlanImportChangeSections(preview: importPreview)

                if !pending.exchange.contexts.isEmpty {
                    Section("Day context") {
                        Toggle("Overwrite existing day context", isOn: $overwriteDayContext)
                        ImportCountRow(label: "Rows in CSV", count: importPreview.dayContextRows)
                        ImportCountRow(label: "Rows to overwrite", count: importPreview.dayContextRowsToApply)
                        ImportCountRow(label: "Rows to ignore", count: importPreview.dayContextRowsIgnored)
                        Text("When enabled, notes and tags from the CSV replace the existing context for those dates. When disabled, CSV day context is ignored.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !importPreview.warnings.isEmpty {
                    Section("Warnings") {
                        ForEach(Array(importPreview.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning)
                                .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("Review Plan Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isApplying)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        applyImport()
                    }
                    .disabled(isApplying)
                }
            }
            .overlay {
                if isApplying {
                    ProgressView("Importing…")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    }
                }
            }
        }

    private func applyImport() {
        isApplying = true
        do {
            let summary = try PlanCSVExchange.apply(
                pending.exchange,
                mode: pending.mode,
                overwriteDayContext: overwriteDayContext,
                in: context
            )
            onComplete(.success(summary))
            dismiss()
        } catch {
            isApplying = false
            onComplete(.failure(error))
        }
    }
}

struct PlanImportSummarySheet: View {
    let summary: PlanCSVExchange.Summary

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(summary.preview.isNewPlan ? "New plan created" : "Existing plan updated")
                        .font(.headline)
                    LabeledContent("Plan", value: summary.planName)
                }

                PlanImportChangeSections(preview: summary.preview, summary: summary)

                Section("Day context") {
                    ImportCountRow(label: "Rows overwritten", count: summary.dayContextCountApplied)
                    ImportCountRow(label: "Rows ignored", count: summary.dayContextCountIgnored)
                }

                if !summary.warnings.isEmpty {
                    Section("Warnings") {
                        ForEach(Array(summary.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning)
                                .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("Plan Import Complete")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PlanImportChangeSections: View {
    let preview: PlanCSVExchange.ImportPreview
    var summary: PlanCSVExchange.Summary?

    var body: some View {
        Section("Plan") {
            LabeledContent("Plan", value: preview.planName)
            if preview.isNewPlan {
                LabeledContent("Action", value: "Create new plan")
            } else {
                LabeledContent("Target", value: preview.targetPlanName)
                if preview.metadataChanges.isEmpty {
                    LabeledContent("Metadata", value: "No changes")
                } else {
                    ForEach(preview.metadataChanges, id: \.self) { change in
                        LabeledContent(change, value: "Updated")
                    }
                }
            }
        }

        Section("Schedule") {
            ImportCountRow(label: "Days added", count: preview.daysToAdd)
            ImportCountRow(label: "Days updated", count: preview.daysToUpdate)
            ImportCountRow(label: "Unlogged days removed", count: preview.daysToRemove)
            ImportCountRow(label: "Days with protected records", count: preview.protectedDayCount)
            ImportCountRow(label: "Schedule entries added", count: preview.scheduleEntriesToAdd)
            ImportCountRow(label: "Unlogged schedule entries removed", count: preview.scheduleEntriesToRemove)
        }

        Section("Exercises") {
            ImportCountRow(label: "Definitions added", count: preview.exerciseDefinitionsToAdd)
            ImportCountRow(label: "Definitions updated", count: preview.exerciseDefinitionsToUpdate)
            ImportCountRow(label: "Logged exercises protected", count: preview.protectedLoggedExerciseCount)
            if preview.missingCatalogExerciseCount > 0 {
                ImportCountRow(label: "Missing catalog exercises", count: preview.missingCatalogExerciseCount)
            }
        }

        Section("Logs and climbs") {
            ImportCountRow(label: summary == nil ? "Logs to import" : "Logs imported", count: summary?.logCount ?? preview.logsToImport)
            ImportCountRow(label: "Existing logs preserved", count: preview.existingLogCount)
            ImportCountRow(label: summary == nil ? "Climbs to import" : "Climbs imported", count: summary?.climbCount ?? preview.climbsToImport)
            ImportCountRow(label: "Linked climbs preserved", count: preview.existingClimbCount)
        }
    }
}

private struct ImportCountRow: View {
    let label: String
    let count: Int

    var body: some View {
        LabeledContent(label, value: count.formatted())
    }
}
