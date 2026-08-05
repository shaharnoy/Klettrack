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

    var body: some View {
        NavigationStack {
            Form {
                Section("Import") {
                    LabeledContent("Plan", value: pending.exchange.plan.name)
                    LabeledContent("Action", value: pending.targetDescription)
                    LabeledContent("Days", value: pending.exchange.days.count.formatted())
                    LabeledContent("Exercises", value: pending.exchange.exercises.count.formatted())
                    LabeledContent("Exercise logs", value: pending.exchange.logs.count.formatted())
                    LabeledContent("Climbs", value: pending.exchange.climbs.count.formatted())
                }

                if !pending.exchange.contexts.isEmpty {
                    Section("Day context") {
                        Toggle("Overwrite existing day context", isOn: $overwriteDayContext)
                        Text("When enabled, notes and tags from the CSV replace the existing context for those dates. When disabled, CSV day context is ignored.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Only logged exercises and linked climbs are protected. Other plan metadata and schedule changes from the CSV will be applied.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !pending.exchange.warnings.isEmpty {
                    Section("Warnings") {
                        ForEach(Array(pending.exchange.warnings.enumerated()), id: \.offset) { _, warning in
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
