//
//  DayContextViews.swift
//  klettrack
//

import SwiftUI
import SwiftData

struct DayTagChip: View {
    let tag: DayTag

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(DayTypeModel.color(for: tag.colorKey))
                .frame(width: 7, height: 7)
            Text(tag.name)
                .lineLimit(1)
        }
        .font(.caption2)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(DayTypeModel.color(for: tag.colorKey).opacity(0.16))
        .foregroundStyle(.primary)
        .clipShape(.rect(cornerRadius: 5))
    }
}

struct DayTagChips: View {
    let tags: [DayTag]

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(tags) { tag in
                    DayTagChip(tag: tag)
                }
            }
        }
    }
}

struct DayTagPresentation: Identifiable {
    let tag: DayTag
    let isSelected: Bool

    var id: UUID { tag.id }
}

@MainActor
enum DayTagPresentationBuilder {
    static func orderedTags(allTags: [DayTag], selectedTags: [DayTag]) -> [DayTagPresentation] {
        let selectedIds = Set(selectedTags.filter { !$0.isHidden }.map(\.id))
        let activeTags = allTags
            .filter { !$0.isHidden }
            .sorted { lhs, rhs in
                if lhs.sort != rhs.sort { return lhs.sort < rhs.sort }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        let selected = activeTags
            .filter { selectedIds.contains($0.id) }
            .map { DayTagPresentation(tag: $0, isSelected: true) }
        let unselected = activeTags
            .filter { !selectedIds.contains($0.id) }
            .map { DayTagPresentation(tag: $0, isSelected: false) }
        return selected + unselected
    }
}

enum DayContextFocusedField: Hashable {
    case note
    case newTag
}

struct DayContextEditorSection: View {

    @Environment(\.modelContext) private var context

    let date: Date
    let dayLog: DayLog?
    let onDayLogChanged: (DayLog?) -> Void
    let focusedField: FocusState<DayContextFocusedField?>.Binding

    @Query(
        filter: #Predicate<DayTag> { $0.isHidden == false },
        sort: [
            SortDescriptor<DayTag>(\DayTag.sort, order: .forward),
            SortDescriptor<DayTag>(\DayTag.name, order: .forward)
        ]
    ) private var tags: [DayTag]

    @State private var noteText = ""
    @State private var newTagName = ""
    @State private var newTagColorKey = "gray"
    @State private var errorMessage: String?

    private var selectedTags: [DayTag] {
        DayLogStore.activeTags(from: dayLog)
    }

    private var presentedTags: [DayTagPresentation] {
        DayTagPresentationBuilder.orderedTags(allTags: tags, selectedTags: selectedTags)
    }

    private var trimmedNewTagName: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowNewTagControls: Bool {
        focusedField.wrappedValue == .newTag || !trimmedNewTagName.isEmpty
    }

    var body: some View {
        Section("Day Context") {
            TextEditor(text: $noteText)
                .frame(height: 120)
                .scrollIndicators(.visible, axes: .vertical)
                .scrollDismissesKeyboard(.interactively)
                .focused(focusedField, equals: .note)
                .accessibilityLabel("Daily note")
                .overlay(alignment: .topLeading) {
                    if noteText.isEmpty {
                        Text("Daily note")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .task(id: noteText) {
                    guard noteText != (dayLog?.note ?? "") else { return }
                    do {
                        try await Task.sleep(for: .milliseconds(350))
                        saveNote()
                    } catch {
                        // The task is cancelled when another keystroke arrives.
                    }
                }

            VStack(alignment: .leading, spacing: 10) {
                if presentedTags.isEmpty {
                    Text("No tags yet")
                        .foregroundStyle(.secondary)
                }

                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(presentedTags) { presentation in
                        DayTagToggleChip(
                            tag: presentation.tag,
                            isSelected: presentation.isSelected,
                            onToggle: { toggle(presentation.tag) }
                        )
                    }

                    NewLabelChip(name: $newTagName, colorKey: newTagColorKey)
                        .focused(focusedField, equals: .newTag)
                        .onSubmit(addTag)
                }

                if shouldShowNewTagControls {
                    inlineTagControls
                }
            }
            .padding(.vertical, 2)
        }
        .onAppear(perform: syncNoteText)
        .onChange(of: dayLog?.id) { _, _ in
            syncNoteText()
        }
        .onChange(of: dayLog?.note) { _, _ in
            syncNoteText()
        }
        .onChange(of: date) { _, _ in
            focusedField.wrappedValue = nil
            syncNoteText()
        }
        .onDisappear {
            focusedField.wrappedValue = nil
            saveNote()
        }
        .alert(errorMessage ?? "", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        }
    }

    private var inlineTagControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ColorKeyPicker(selection: $newTagColorKey)

            HStack {
                Button("Cancel", role: .cancel, action: resetNewTagInput)
                    .buttonStyle(.borderless)
                Spacer()
                Button("Create", action: addTag)
                    .buttonStyle(.borderless)
                    .disabled(trimmedNewTagName.isEmpty)
            }
        }
    }

    private func syncNoteText() {
        let currentNote = dayLog?.note ?? ""
        if noteText != currentNote {
            noteText = currentNote
        }
    }

    private func editableDayLog(createIfMissing: Bool = true) -> DayLog? {
        let editable = DayLogStore.dayLog(for: date, in: context, createIfMissing: createIfMissing)
        if editable?.id != dayLog?.id {
            onDayLogChanged(editable)
        }
        return editable
    }

    private func saveNote() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || dayLog != nil else { return }
        guard let editable = editableDayLog() else { return }
        if editable.note != trimmed {
            DayLogStore.setNote(noteText, for: editable)
            try? context.save()
            onDayLogChanged(editable)
        }
    }

    private func toggle(_ tag: DayTag) {
        guard let editable = editableDayLog() else { return }
        let isAssigned = DayLogStore.activeTags(from: editable).contains { $0.id == tag.id }
        DayLogStore.setTag(tag, assigned: !isAssigned, to: editable)
        try? context.save()
        onDayLogChanged(editable)
    }

    private func resetNewTagInput() {
        newTagName = ""
        newTagColorKey = "gray"
        focusedField.wrappedValue = nil
    }

    private func addTag() {
        let trimmed = trimmedNewTagName
        guard !trimmed.isEmpty else { return }
        guard DayLogStore.activeTag(named: trimmed, in: context) == nil else {
            errorMessage = "A tag with this name already exists."
            return
        }
        guard let editable = editableDayLog(),
              let tag = DayLogStore.createTag(name: trimmed, colorKey: newTagColorKey, in: context)
        else { return }
        DayLogStore.setTag(tag, assigned: true, to: editable)
        try? context.save()
        onDayLogChanged(editable)
        resetNewTagInput()
    }
}

private struct NewLabelChip: View {
    @Binding var name: String
    let colorKey: String

    private var color: Color {
        DayTypeModel.color(for: colorKey)
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            TextField("New label", text: $name)
                .font(.caption)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .lineLimit(1)
                .frame(width: 70)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.secondary.opacity(0.12))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.25), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

private struct DayTagToggleChip: View {
    let tag: DayTag
    let isSelected: Bool
    let onToggle: () -> Void

    private var color: Color {
        DayTypeModel.color(for: tag.colorKey)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                }

                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(tag.name)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? color.opacity(0.22) : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? color : .secondary.opacity(0.35), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
        .accessibilityLabel(tag.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Double tap to remove this tag from the day." : "Double tap to assign this tag to the day.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ColorKeyPicker: View {
    @Binding var selection: String

    private var sortedKeys: [String] {
        let preferred = ["green","blue","indigo","purple","pink","red","orange","yellow","mint","teal","cyan","brown","gray","black","white"]
        let allowed = Array(DayTypeModel.allowedColorKeys)
        let remaining = allowed.filter { !preferred.contains($0) }.sorted()
        return preferred.filter { allowed.contains($0) } + remaining
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
            ForEach(sortedKeys, id: \.self) { key in
                Button {
                    selection = key
                } label: {
                    ZStack {
                        Circle()
                            .fill(DayTypeModel.color(for: key))
                            .frame(width: 28, height: 28)
                        if selection == key {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(key)
                .accessibilityValue(selection == key ? "Selected" : "Not selected")
            }
        }
        .padding(.vertical, 4)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        return CGSize(
            width: width,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * rowSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentItems: [Item] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width
            if proposedWidth > width, !currentItems.isEmpty {
                rows.append(Row(items: currentItems, height: currentHeight))
                currentItems = [Item(index: index, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(Item(index: index, size: size))
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(Row(items: currentItems, height: currentHeight))
        }
        return rows
    }

    private struct Row {
        let items: [Item]
        let height: CGFloat
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }
}
