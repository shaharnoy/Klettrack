//
//  SetLogPanel.swift
//  Klettrack
//
//  Per-set record for a rep-based exercise: pick a set, dial in what you lifted.
//

import SwiftUI

/// The card under a rep-based timer: a chip per set, and the controls for whichever
/// one is selected.
///
/// Visible both while waiting on a set and while resting after one, so a weight can
/// be corrected or the next set dialled in without leaving the screen. The Done
/// button only appears when a set is actually waiting.
struct SetLogPanel: View {
    let timerManager: TimerManager
    let sequence: TimerManager.SetSequence

    private var editing: LoggedSet? {
        timerManager.setLogs.indices.contains(timerManager.editingSetIndex)
            ? timerManager.setLogs[timerManager.editingSetIndex]
            : nil
    }

    var body: some View {
        VStack(spacing: 16) {
            SetChipStrip(timerManager: timerManager, shape: sequence.shape)

            if let editing {
                if sequence.shape.takesLoad {
                    SetWeightStepper(
                        timerManager: timerManager,
                        index: timerManager.editingSetIndex,
                        weightKg: editing.weightKg,
                        seedWeightKg: timerManager.seedWeightKg,
                        status: timerManager.setStatus(at: timerManager.editingSetIndex)
                    )
                }

                SetEffortBar(
                    timerManager: timerManager,
                    index: timerManager.editingSetIndex,
                    rpe: editing.rpe,
                    unit: sequence.shape.unitLabel.lowercased()
                )

                SetNoteField(
                    timerManager: timerManager,
                    index: timerManager.editingSetIndex,
                    note: editing.note,
                    unit: sequence.shape.unitLabel.lowercased()
                )
            }

            if timerManager.isAwaitingUser {
                Button {
                    timerManager.confirmSet()
                } label: {
                    Label(sequence.isFinalSet ? "Finish" : "Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FullWidthTimerButtonStyle(color: .green))
                .accessibilityLabel(
                    sequence.isFinalSet
                        ? "Finish exercise"
                        : "\(sequence.shape.unitLabel.capitalized) \(sequence.currentSet) done, start \(sequence.restSeconds / 60) minute rest"
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(.rect(cornerRadius: 16))
    }
}

/// The run of set chips. Tapping one selects it for editing without touching the timer.
///
/// Wraps rather than scrolls: `FlowLayout` sizes to its content, where a horizontal
/// `ScrollView` is greedy in the cross axis and would push the rest of the card down.
/// Wrapping also keeps every set on screen instead of hiding the later ones.
struct SetChipStrip: View {
    let timerManager: TimerManager
    let shape: ExerciseShape

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(timerManager.setLogs.indices, id: \.self) { index in
                Button {
                    timerManager.selectSet(at: index)
                } label: {
                    SetChip(
                        number: index + 1,
                        unit: shape.unitLabel,
                        log: timerManager.setLogs[index],
                        status: timerManager.setStatus(at: index),
                        isSelected: index == timerManager.editingSetIndex
                    )
                }
                .buttonStyle(.plain)
            }

            // Attempts only: a planned set count is a prescription, but a try count is
            // a result. Sitting at the end of the strip it reads as "one more".
            if shape == .attempts {
                Button {
                    timerManager.addSet()
                } label: {
                    AddSetChip()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add another try")
            }
        }
    }
}

struct SetChip: View {
    let number: Int
    var unit: String = "SET"
    let log: LoggedSet
    let status: TimerManager.SetStatus
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text("\(unit) \(number)")
                    .font(.caption2.weight(.semibold))
                if status == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            // Tint only the headline text. A blanket tint would drag the weight
            // caption's `.secondary` down to a faded accent and lose its contrast.
            .foregroundStyle(isSelected ? Color.accentColor : .primary)

            if let reps = log.reps {
                Text("\(reps, format: .number.precision(.fractionLength(0))) reps")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }

            if let weight = log.weightKg, weight > 0 {
                Text("\(weight, format: .number.precision(.fractionLength(0...1))) kg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: 78)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(.systemGray5))
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
        .accessibilityLabel("\(unit.capitalized) \(number)\(status == .done ? ", done" : "")")
        .accessibilityHint("Edit this \(unit.lowercased())")
    }
}

/// The trailing "+" in an attempts strip. Dashed rather than filled so it reads as an
/// empty slot to be claimed, not as a try already logged.
struct AddSetChip: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 14)
            // Matches SetChip's two-line height so the strip doesn't go ragged.
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 46)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        Color.accentColor.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
            }
    }
}

/// Weight for one set. Shown only where load is part of the exercise — see
/// `ExerciseShape.takesLoad`, which the catalog now records per exercise. A limit
/// boulder has no kg to dial in, and an empty box there is a question the athlete
/// can't answer.
struct SetWeightStepper: View {
    let timerManager: TimerManager
    let index: Int
    let weightKg: Double?
    let seedWeightKg: Double?
    let status: TimerManager.SetStatus

    /// Small enough for fingerboard work, coarse enough to reach a working weight fast.
    private static let step: Double = 2.5

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Resistance +/− (kg)")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 0) {
                    Button("Less", systemImage: "minus") {
                        adjust(by: -Self.step)
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 34)

                    Divider().frame(height: 22)

                    SetWeightField(timerManager: timerManager, index: index, weightKg: weightKg)
                        // The field's text is `@State`, and the panel keeps its identity
                        // across a set change. Without an identity of its own the field
                        // would go on showing the previous set's digits while committing
                        // them to the new set's log.
                        .id(index)

                    Divider().frame(height: 22)

                    Button("More", systemImage: "plus") {
                        adjust(by: Self.step)
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 34)
                }
                // A TextField takes all the width it is offered, which would stretch
                // this box across the card and push `+` away from `−`. Hugging the
                // contents keeps the three controls together and still grows with
                // Dynamic Type.
                .fixedSize(horizontal: true, vertical: false)
                .background(Color(.systemGray5))
                .clipShape(.rect(cornerRadius: 8))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Set \(index + 1)")
                        .font(.subheadline)
                    if status == .done {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if let seedWeightKg, seedWeightKg > 0 {
                    Text("Last: \(seedWeightKg, format: .number.precision(.fractionLength(0...1))) kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func adjust(by delta: Double) {
        timerManager.updateSet(at: index) { set in
            // Never negative: this is added load, and assistance isn't modelled.
            let updated = max(0, (set.weightKg ?? 0) + delta)
            set.weightKg = updated
        }
    }
}

/// The editable weight itself. Tapping it opens a decimal pad, so getting from 30 to
/// 47.5 doesn't mean seven taps on `+`.
struct SetWeightField: View {
    let timerManager: TimerManager
    let index: Int
    let weightKg: Double?

    @State private var text = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        TextField("0", text: $text)
            .keyboardType(.decimalPad)
            .focused($isEditing)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit())
            .frame(minWidth: 52)
            .accessibilityLabel("Resistance in kilograms for set \(index + 1)")
            .onAppear { text = decimalText(weightKg) }
            .onChange(of: weightKg) { _, newValue in
                // The +/− buttons edit the same number. Don't fight live typing.
                guard !isEditing else { return }
                text = decimalText(newValue)
            }
            .onChange(of: text) { _, newValue in
                commit(newValue)
            }
            .toolbar {
                // A decimal pad has no Return key, so without this there is no way to
                // put the keyboard away.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditing = false }
                }
            }
    }

    /// Written through on every keystroke rather than on commit: a decimal pad never
    /// submits, so waiting for focus to move risks logging the previous weight when
    /// the user types and taps Done straight away.
    private func commit(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Cleared means bodyweight, which the model spells as no weight at all.
            timerManager.updateSet(at: index) { $0.weightKg = nil }
            return
        }
        // Half-typed or unparseable: leave the recorded value alone.
        guard let value = userDecimal(trimmed) else { return }
        timerManager.updateSet(at: index) { $0.weightKg = max(0, value) }
    }
}

/// "How hard was this set?" — five steps, tap to rate, tap the active one to clear.
///
/// The one per-set field that applies to every shape: with no load to record, this and
/// the note are what the books call the quality of the attempt.
struct SetEffortBar: View {
    let timerManager: TimerManager
    let index: Int
    let rpe: Int?
    var unit: String = "set"

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("How hard was this \(unit)?")
                    .font(.subheadline)
                Spacer()
                Text(LoggedSet.effortLabel(for: rpe) ?? "—")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(rpe == nil ? .secondary : .primary)
            }

            HStack(spacing: 6) {
                ForEach(LoggedSet.effortLabels.indices, id: \.self) { step in
                    Button {
                        rate(step + 1)
                    } label: {
                        // A filled bar, not a labelled control: the segment's meaning is
                        // its position, and the label above names the current rating.
                        RoundedRectangle(cornerRadius: 4)
                            .fill(step < (rpe ?? 0) ? Color.accentColor : Color(.systemGray5))
                            .frame(height: 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LoggedSet.effortLabels[step])
                    .accessibilityAddTraits(step + 1 == rpe ? [.isSelected] : [])
                }
            }
        }
    }

    private func rate(_ value: Int) {
        timerManager.updateSet(at: index) { set in
            set.rpe = (set.rpe == value) ? nil : value
        }
    }
}

/// A note against one set, hidden behind "Add Note" until wanted.
struct SetNoteField: View {
    let timerManager: TimerManager
    let index: Int
    let note: String?
    var unit: String = "set"

    @State private var isExpanded = false

    private var text: Binding<String> {
        Binding(
            get: { note ?? "" },
            set: { newValue in
                timerManager.updateSet(at: index) { set in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    set.note = trimmed.isEmpty ? nil : newValue
                }
            }
        )
    }

    var body: some View {
        if isExpanded || !(note ?? "").isEmpty {
            TextField("Note for this \(unit)", text: text, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
        } else {
            Button("Add Note", systemImage: "plus") {
                isExpanded = true
            }
            .font(.subheadline)
        }
    }
}

/// Previous / next set, flanking whatever the timer is currently showing.
struct SetNavigationRow: View {
    let timerManager: TimerManager
    let sequence: TimerManager.SetSequence
    let label: String
    let labelColor: Color

    var body: some View {
        HStack {
            Button("Previous set", systemImage: "chevron.left") {
                timerManager.previousSet()
            }
            .labelStyle(.iconOnly)
            .disabled(sequence.currentSet <= 1)

            Spacer()

            Text(label)
                .font(.title3.weight(.semibold))
                .foregroundStyle(labelColor)

            Spacer()

            Button("Next set", systemImage: "chevron.right") {
                timerManager.nextSet()
            }
            .labelStyle(.iconOnly)
        }
        .font(.title2)
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}
