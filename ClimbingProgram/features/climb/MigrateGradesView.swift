import SwiftData
import SwiftUI

struct MigrateGradesView: View {
    fileprivate struct GradeMappingDraft: Identifiable, Equatable {
        let id = UUID()
        let oldGrade: String
        let count: Int
        var newGrade: String = ""
    }

    private struct ResultAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    fileprivate enum FocusedField: Hashable {
        case newGrade(UUID)
    }

    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\ClimbGym.name, order: .forward)]) private var gyms: [ClimbGym]

    @State private var selectedGym = ""
    @State private var mappingDrafts: [GradeMappingDraft] = []
    @State private var showingConfirmation = false
    @State private var resultAlert: ResultAlert?
    @FocusState private var focusedField: FocusedField?

    private var gymNames: [String] {
        gyms
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var mappings: [GradeMigrationService.Mapping] {
        mappingDrafts.map {
            GradeMigrationService.Mapping(
                oldGrade: $0.oldGrade,
                newGrade: $0.newGrade
            )
        }
    }

    private var previewSummary: GradeMigrationService.Summary {
        GradeMigrationService.preview(in: context, gym: selectedGym, mappings: mappings)
    }

    private var canMigrate: Bool {
        !selectedGym.isEmpty && previewSummary.count > 0
    }

    private var confirmationMessage: String {
        guard !previewSummary.rows.isEmpty else {
            return "No grades will be changed."
        }

        let rows = previewSummary.rows.map { row in
            "\(row.count) climb\(row.count == 1 ? "" : "s"): \(row.oldGrade) -> \(row.newGrade)"
        }

        return """
        This will change \(previewSummary.count) climb\(previewSummary.count == 1 ? "" : "s") at \(selectedGym):

        \(rows.joined(separator: "\n"))

        The migration is based on the current grades before any row is changed, so remapping chains like 4 -> 5 and 5 -> 6 will not cascade.
        """
    }

    var body: some View {
        List {
            gymSection
            mappingsSection
            previewSection
        }
        .navigationTitle("Migrate Grades")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: selectedGym) {
            loadMappingDrafts()
        }
        .safeAreaInset(edge: .bottom) {
            migrateButton
        }
        .alert("Migrate Grades?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Migrate", role: .destructive) {
                runMigration()
            }
        } message: {
            Text(confirmationMessage)
        }
        .alert(item: $resultAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var gymSection: some View {
        Section {
            Picker("Gym", selection: $selectedGym) {
                Text("Select Gym").tag("")
                ForEach(gymNames, id: \.self) { gym in
                    Text(gym).tag(gym)
                }
            }
            .disabled(gymNames.isEmpty)
        } header: {
            Text("Gym")
        }
    }

    private var mappingsSection: some View {
        Section {
            if gymNames.isEmpty {
                ContentUnavailableView(
                    "No Gyms",
                    systemImage: "building.2",
                    description: Text("Add gyms before migrating grades.")
                )
            } else if selectedGym.isEmpty {
                ContentUnavailableView(
                    "Select Gym",
                    systemImage: "building.2",
                    description: Text("Choose a gym to see its logged grades.")
                )
            } else if mappingDrafts.isEmpty {
                ContentUnavailableView(
                    "No Grades",
                    systemImage: "number",
                    description: Text("This gym does not have logged grades yet.")
                )
            } else {
                GradeMappingHeader()
                ForEach($mappingDrafts) { $draft in
                    GradeMappingRow(
                        draft: $draft,
                        focusedField: $focusedField
                    )
                }
            }
        } header: {
            Text("Grade Mapping")
        } footer: {
            Text("Leave a target grade blank to keep that grade unchanged.")
        }
    }

    private var previewSection: some View {
        Section {
            LabeledContent("Affected Climbs") {
                Text(previewSummary.count, format: .number)
            }

            if previewSummary.rows.isEmpty {
                Text("No grade changes selected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(previewSummary.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(row.oldGrade) -> \(row.newGrade)")
                        HStack(spacing: 8) {
                            Text(row.count, format: .number)
                            Text(row.count == 1 ? "climb" : "climbs")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Preview")
        }
    }

    private var migrateButton: some View {
        Button {
            focusedField = nil
            showingConfirmation = true
        } label: {
            Label("Migrate Grades", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canMigrate)
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func loadMappingDrafts() {
        focusedField = nil
        mappingDrafts = GradeMigrationService
            .gradeCounts(in: context, gym: selectedGym)
            .map { GradeMappingDraft(oldGrade: $0.grade, count: $0.count) }
    }

    private func runMigration() {
        do {
            let summary = try GradeMigrationService.migrateAll(
                in: context,
                gym: selectedGym,
                mappings: mappings
            )
            loadMappingDrafts()
            resultAlert = ResultAlert(
                title: "Migration Complete",
                message: "Updated \(summary.count) climb\(summary.count == 1 ? "" : "s")."
            )
        } catch {
            resultAlert = ResultAlert(
                title: "Migration Failed",
                message: error.localizedDescription
            )
        }
    }
}

private struct GradeMappingHeader: View {
    private let targetColumnWidth: CGFloat = 112

    var body: some View {
        HStack(spacing: 12) {
            Text("Current")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Target")
                .frame(width: targetColumnWidth, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct GradeMappingRow: View {
    private let targetColumnWidth: CGFloat = 112

    @Binding var draft: MigrateGradesView.GradeMappingDraft
    var focusedField: FocusState<MigrateGradesView.FocusedField?>.Binding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.oldGrade)
                    .font(.body)
                Text("\(draft.count) \(draft.count == 1 ? "climb" : "climbs")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("No change", text: $draft.newGrade)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focusedField, equals: .newGrade(draft.id))
                .submitLabel(.done)
                .frame(width: targetColumnWidth, alignment: .leading)
                .onSubmit {
                    focusedField.wrappedValue = nil
                }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        MigrateGradesView()
    }
    .modelContainer(for: [ClimbEntry.self, ClimbGym.self], inMemory: true)
}
