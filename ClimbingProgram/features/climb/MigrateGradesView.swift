import SwiftData
import SwiftUI

struct MigrateGradesView: View {
    private struct ResultAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum FocusedField: Hashable {
        case newGrade
        case newFeelsLikeGrade
    }

    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\ClimbGym.name, order: .forward)]) private var gyms: [ClimbGym]

    @State private var selectedGym = ""
    @State private var selectedOldGrade = ""
    @State private var newGrade = ""
    @State private var newFeelsLikeGrade = ""
    @State private var showingConfirmation = false
    @State private var resultAlert: ResultAlert?
    @FocusState private var focusedField: FocusedField?

    private var gymNames: [String] {
        gyms
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var oldGradeOptions: [String] {
        GradeMigrationService.availableOldGrades(in: context, gym: selectedGym)
    }

    private var trimmedNewGrade: String {
        newGrade.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewFeelsLikeGrade: String {
        newFeelsLikeGrade.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var affectedCount: Int {
        GradeMigrationService.matchingCount(in: context, gym: selectedGym, oldGrade: selectedOldGrade)
    }

    private var canMigrate: Bool {
        !selectedGym.isEmpty &&
        !selectedOldGrade.isEmpty &&
        !trimmedNewGrade.isEmpty
    }

    private var confirmationMessage: String {
        var message = "This will change \(affectedCount) climb\(affectedCount == 1 ? "" : "s") at \(selectedGym) from \(selectedOldGrade) to \(trimmedNewGrade). You can migrate back later by running this again with the grades swapped."
        if !trimmedNewFeelsLikeGrade.isEmpty {
            message += "\n\nMy Grade will be set to \(trimmedNewFeelsLikeGrade)."
        }
        return message
    }

    var body: some View {
        List {
            migrationSection
            previewSection
        }
        .navigationTitle("Migrate Grades")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: selectedGym) {
            resetOldGradeIfNeeded()
        }
        .safeAreaInset(edge: .bottom) {
            migrateButton
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
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

    private var migrationSection: some View {
        Section {
            Picker("Gym", selection: $selectedGym) {
                Text("Select Gym").tag("")
                ForEach(gymNames, id: \.self) { gym in
                    Text(gym).tag(gym)
                }
            }
            .disabled(gymNames.isEmpty)

            Picker("Old Grade", selection: $selectedOldGrade) {
                Text("Select Grade").tag("")
                ForEach(oldGradeOptions, id: \.self) { grade in
                    Text(grade).tag(grade)
                }
            }
            .disabled(selectedGym.isEmpty || oldGradeOptions.isEmpty)

            TextField("New grade", text: $newGrade)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .newGrade)
                .submitLabel(.done)
                .onSubmit {
                    focusedField = nil
                }

            TextField("New My Grade (optional)", text: $newFeelsLikeGrade)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .newFeelsLikeGrade)
                .submitLabel(.done)
                .onSubmit {
                    focusedField = nil
                }
        } header: {
            Text("Migration")
        } footer: {
            Text("Blank My Grade leaves existing My Grade values unchanged.")
        }
    }

    private var migrateButton: some View {
        Button {
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

    private var previewSection: some View {
        Section {
            if gymNames.isEmpty {
                ContentUnavailableView(
                    "No Gyms",
                    systemImage: "building.2",
                    description: Text("Add gyms before migrating grades.")
                )
            } else if !selectedGym.isEmpty && oldGradeOptions.isEmpty {
                ContentUnavailableView(
                    "No Grades",
                    systemImage: "number",
                    description: Text("This gym does not have logged grades yet.")
                )
            } else {
                LabeledContent("Affected Climbs") {
                    Text(affectedCount, format: .number)
                }
                if !selectedGym.isEmpty {
                    LabeledContent("Gym", value: selectedGym)
                }
                if !selectedOldGrade.isEmpty {
                    LabeledContent("Old Grade", value: selectedOldGrade)
                }
            }
        } header: {
            Text("Preview")
        }
    }

    private func resetOldGradeIfNeeded() {
        if !oldGradeOptions.contains(selectedOldGrade) {
            selectedOldGrade = ""
        }
    }

    private func runMigration() {
        do {
            let summary = try GradeMigrationService.migrate(
                in: context,
                gym: selectedGym,
                oldGrade: selectedOldGrade,
                newGrade: newGrade,
                newFeelsLikeGrade: newFeelsLikeGrade
            )
            newGrade = ""
            newFeelsLikeGrade = ""
            resetOldGradeIfNeeded()
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

#Preview {
    NavigationStack {
        MigrateGradesView()
    }
    .modelContainer(for: [ClimbEntry.self, ClimbGym.self], inMemory: true)
}
