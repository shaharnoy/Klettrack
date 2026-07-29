//
//  ExerciseLogSheet.swift
//  Klettrack
//
//  The exercise log form, shared by the plan day editor and the timer.
//

import SwiftUI
import SwiftData

/// Log one exercise against a day. Used from the plan day editor's log button and
/// offered automatically when an exercise-launched timer finishes.
struct ExerciseLogSheet: View {
    struct Prefill {
        var reps: String = ""
        var sets: String = ""
        var duration: String = ""
        var weight: String = ""
        var grade: String = ""
        var notes: String = ""
        /// Per-set detail from the timer. Saved alongside the fields above, which are
        /// its rollup.
        var loggedSets: [LoggedSet] = []

        init(
            reps: String = "",
            sets: String = "",
            duration: String = "",
            weight: String = "",
            grade: String = "",
            notes: String = "",
            loggedSets: [LoggedSet] = []
        ) {
            self.reps = reps
            self.sets = sets
            self.duration = duration
            self.weight = weight
            self.grade = grade
            self.notes = notes
            self.loggedSets = loggedSets
        }

        /// Convenience for the timer: numbers in, strings out, blanks for anything unknown.
        init(reps: Int?, sets: Int?, durationSeconds: Int?) {
            self.reps = reps.map(String.init) ?? ""
            self.sets = sets.map(String.init) ?? ""
            self.duration = Self.minutes(from: durationSeconds)
        }

        /// A rep-based timer's per-set record. The top fields come from the rollup, so
        /// what the form shows is what was actually done rather than what was planned.
        init(loggedSets: [LoggedSet], durationSeconds: Int?) {
            self.loggedSets = loggedSets
            let rollup = loggedSets.rollup
            self.reps = decimalText(rollup.reps)
            self.sets = decimalText(rollup.sets)
            self.weight = decimalText(rollup.weightKg)
            self.duration = Self.minutes(from: durationSeconds)
        }

        /// The log form takes minutes; a short rest must not round down to "0".
        private static func minutes(from seconds: Int?) -> String {
            seconds.map { String(max(1, Int((Double($0) / 60).rounded()))) } ?? ""
        }

        /// Write these values as one logged item on the given day.
        ///
        /// This is the Save button's whole effect apart from dismissing the sheet, which
        /// is what makes it testable: the button and the test drive the same code, rather
        /// than a test hand-assembling a `SessionItem` and proving only that SwiftData
        /// stores what you put in it.
        ///
        /// `Prefill` already held exactly these fields as strings to seed the form; this
        /// is the same struct read back out of it.
        @discardableResult
        func commit(
            exerciseName: String,
            date: Date,
            planId: UUID?,
            planName: String?,
            in context: ModelContext
        ) -> SessionItem {
            let item = SessionItem(
                exerciseName: exerciseName,
                planSourceId: planId,
                planName: planName,
                reps: userDecimal(reps),
                sets: userDecimal(sets),
                weightKg: userDecimal(weight),
                grade: Self.trimmedOrNil(grade),
                notes: Self.trimmedOrNil(notes),
                duration: userDecimal(duration),
                // The per-set record stands even if the fields above were hand-edited:
                // those are the rollup, this is what the timer actually captured.
                loggedSets: loggedSets
            )
            findOrCreateSession(for: date, in: context).items.append(item)
            try? context.save()
            return item
        }

        /// An empty field means "not recorded", which the model spells as nil — never
        /// as an empty string, which would render as a blank line in the log.
        private static func trimmedOrNil(_ text: String) -> String? {
            let value = text.trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
    }

    let exerciseName: String
    let date: Date
    let planId: UUID?
    let planName: String?
    var prefill: Prefill = .init()
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var inputReps: String = ""
    @State private var inputSets: String = ""
    @State private var inputDuration: String = ""
    @State private var inputWeight: String = ""
    @State private var inputGrade: String = ""
    @State private var inputNotes: String = ""
    @State private var didLoadPrefill = false

    /// Hidden for exercises that take no added load — but never hidden while a weight
    /// is actually present, or an imported value would become invisible *and*
    /// uneditable. Reads the catalog by name; unknown names keep the field.
    private var showsWeight: Bool {
        !inputWeight.isEmpty
            || !prefill.weight.isEmpty
            || exerciseShape(named: exerciseName, in: context).takesLoad
    }

    var body: some View {
        NavigationStack {
            form
                .listStyle(.insetGrouped)
                .navigationTitle("Quick Log")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                    }
                }
        }
        .onAppear {
            // Only once — re-appearing must not discard edits in progress.
            guard !didLoadPrefill else { return }
            didLoadPrefill = true
            inputReps = prefill.reps
            inputSets = prefill.sets
            inputDuration = prefill.duration
            inputWeight = prefill.weight
            inputGrade = prefill.grade
            inputNotes = prefill.notes
        }
    }

    private var form: some View {
        Form {
            Section { Text(exerciseName).font(.headline) }

            Section {
                LabeledContent {
                    TextField("e.g. 10", text: $inputReps)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Reps", systemImage: "repeat")
                }

                LabeledContent {
                    TextField("e.g. 3", text: $inputSets)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Sets", systemImage: "square.grid.3x3")
                }

                LabeledContent {
                    TextField("e.g. 20", text: $inputDuration)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Duration (min)", systemImage: "clock")
                }

                if showsWeight {
                    LabeledContent {
                        TextField("e.g. 12.5", text: $inputWeight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Weight (kg)", systemImage: "scalemass")
                    }
                }

                LabeledContent {
                    TextField("e.g. 6a+", text: $inputGrade)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Grade", systemImage: "star")
                }
            } header: {
                Text("LOG FIELDS").textCase(nil)
            } footer: {
                Text("Leave a field empty if it doesn't apply.")
            }

            Section("Preview") {
                LogMetricRow(
                    reps: inputReps.isEmpty ? nil : inputReps,
                    sets: inputSets.isEmpty ? nil : inputSets,
                    weight: inputWeight.isEmpty ? nil : inputWeight,
                    grade: inputGrade.isEmpty ? nil : inputGrade,
                    duration: inputDuration.isEmpty ? nil : inputDuration
                )

                LoggedSetsRow(sets: prefill.loggedSets)
            }

            Section("Notes") {
                TextField("Notes (optional)", text: $inputNotes, axis: .vertical)
                    .lineLimit(1...3)
            }
        }
    }

    private func save() {
        Prefill(
            reps: inputReps,
            sets: inputSets,
            duration: inputDuration,
            weight: inputWeight,
            grade: inputGrade,
            notes: inputNotes,
            // Not editable in the form — the timer captured it, the fields above are
            // its rollup.
            loggedSets: prefill.loggedSets
        )
        .commit(
            exerciseName: exerciseName,
            date: date,
            planId: planId,
            planName: planName,
            in: context
        )

        onSaved()
        dismiss()
    }
}
