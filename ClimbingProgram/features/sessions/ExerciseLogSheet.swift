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

        init(reps: String = "", sets: String = "", duration: String = "", weight: String = "", grade: String = "", notes: String = "") {
            self.reps = reps
            self.sets = sets
            self.duration = duration
            self.weight = weight
            self.grade = grade
            self.notes = notes
        }

        /// Convenience for the timer: numbers in, strings out, blanks for anything unknown.
        init(reps: Int?, sets: Int?, durationSeconds: Int?) {
            self.reps = reps.map(String.init) ?? ""
            self.sets = sets.map(String.init) ?? ""
            // The log form takes minutes.
            self.duration = durationSeconds.map { String(max(1, Int((Double($0) / 60).rounded()))) } ?? ""
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

                LabeledContent {
                    TextField("e.g. 12.5", text: $inputWeight)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Weight (kg)", systemImage: "scalemass")
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
            }

            Section("Notes") {
                TextField("Notes (optional)", text: $inputNotes, axis: .vertical)
                    .lineLimit(1...3)
            }
        }
    }

    private func save() {
        let session = findOrCreateSession(for: date, in: context)
        session.items.append(
            SessionItem(
                exerciseName: exerciseName,
                planSourceId: planId,
                planName: planName,
                reps: number(inputReps),
                sets: number(inputSets),
                weightKg: number(inputWeight),
                grade: trimmed(inputGrade),
                notes: trimmed(inputNotes),
                duration: number(inputDuration)
            )
        )
        try? context.save()
        onSaved()
        dismiss()
    }

    private func number(_ text: String) -> Double? {
        Double(text.replacing(",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
