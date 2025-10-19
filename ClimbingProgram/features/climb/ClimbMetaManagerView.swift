//  ClimbMetaManagerView.swift
//  Klettrack
//  Created by Shahar Noy on 14.10.25.
//

import SwiftUI
import SwiftData

struct ClimbMetaManagerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // Fetch all styles, gyms, days
    @Query(sort: [SortDescriptor(\ClimbStyle.name, order: .forward)]) private var styles: [ClimbStyle]
    @Query(sort: [SortDescriptor(\ClimbGym.name, order: .forward)]) private var gyms: [ClimbGym]
    // Exclude hidden (soft-deleted) day types from UI lists
    @Query(
        filter: #Predicate<DayTypeModel> { $0.isHidden == false },
        sort: [SortDescriptor(\DayTypeModel.name, order: .forward)]
    ) private var days: [DayTypeModel]
    
    // Add / rename state
    @State private var showingAddStyle = false
    @State private var showingAddGym = false
    @State private var showingAddDay = false

    @State private var styleDraft = ""
    @State private var gymDraft = ""
    @State private var dayDraft = ""

    @State private var renamingStyle: ClimbStyle? = nil
    @State private var renamingGym: ClimbGym? = nil
    @State private var renamingDay: DayTypeModel? = nil
    @State private var renameDraft = ""

    // Restore/Add defaults state
    @State private var showingRestoreAlert = false

    // Replace String? alert with Identifiable wrapper for simpler alert(item:)
    private struct InfoAlert: Identifiable {
        let id = UUID()
        let message: String
    }
    @State private var resultAlert: InfoAlert? = nil

    // Color picker state
    @State private var changingDayColor: DayTypeModel? = nil

    var body: some View {
        NavigationStack {
            List {
                stylesSection
                daysSection
                gymsSection
            }
            .navigationTitle("Styles & Gyms")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Add defaults without deleting
                        Button {
                            addMissingDefaults()
                        } label: {
                            Label("Recover deleted defaults", systemImage: "plus.app")
                        }
                        // Full restore (non-destructive reset)
                        Button {
                            showingRestoreAlert = true
                        } label: {
                            Label("Reset back to default values", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }

            // MARK: - Sheets (Add)
            .sheet(isPresented: $showingAddStyle) {
                NameOnlySheet(title: "New Style",
                              placeholder: "e.g. Slab, Power, Coordination…",
                              name: $styleDraft) {
                    let trimmed = styleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    context.insert(ClimbStyle(name: trimmed, isDefault: false))
                    try? context.save()
                }
            }
            .sheet(isPresented: $showingAddGym) {
                NameOnlySheet(title: "New Gym",
                              placeholder: "e.g. Ostbloc, Elektra…",
                              name: $gymDraft) {
                    let trimmed = gymDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    context.insert(ClimbGym(name: trimmed, isDefault: false))
                    try? context.save()
                }
            }
            .sheet(isPresented: $showingAddDay) {
                DayEditSheet(
                    title: "New Day",
                    initialName: "",
                    initialColorKey: "gray"
                ) { newName, newColorKey in
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return false }

                    // Protection: disallow using a default day name (show alert, keep sheet open)
                    let defaultNamesLC = Set(ClimbingDefaults.defaultDayTypes.map {
                        $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    })
                    if defaultNamesLC.contains(trimmed.lowercased()) {
                        resultAlert = InfoAlert(message: "“\(trimmed)” is a default day type. Edit that default instead.")
                        return false
                    }

                    let key = trimmed
                        .lowercased()
                        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                    let safeColor = DayTypeModel.allowedColorKeys.contains(newColorKey) ? newColorKey : "gray"
                    context.insert(DayTypeModel(
                        key: key,
                        name: trimmed,
                        order: (days.map { $0.order }.max() ?? 0) + 10,
                        colorKey: safeColor
                    ))
                    try? context.save()
                    return true
                }
            }



            // MARK: - Sheets (Rename)
            .sheet(item: $renamingStyle) { style in
                NameOnlySheet(title: "Rename Style",
                              placeholder: "New name",
                              name: $renameDraft) {
                    let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    style.name = trimmed
                    try? context.save()
                }
            }
            .sheet(item: $renamingGym) { gym in
                NameOnlySheet(title: "Rename Gym",
                              placeholder: "New name",
                              name: $renameDraft) {
                    let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    gym.name = trimmed
                    try? context.save()
                }
            }
            .sheet(item: $renamingDay) { day in
                DayEditSheet(
                    title: "Edit Day",
                    initialName: day.name,
                    initialColorKey: day.colorKey
                ) { newName, newColorKey in
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return false }
                    day.name = trimmed
                    if DayTypeModel.allowedColorKeys.contains(newColorKey) {
                        day.colorKey = newColorKey
                    }
                    try? context.save()
                    return true
                }
            }


            // MARK: - Alerts
            .alert("Reset defaults?", isPresented: $showingRestoreAlert) {
                Button("Reset", role: .destructive) {
                    nonDestructiveResetDayTypes()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will reset the default Day Types’ names, colors and order without deleting your custom types. Existing plans will remain intact.")
            }
            .alert(item: $resultAlert) { info in
                Alert(title: Text(info.message))
            }
        }
    }

    // MARK: - Sections (extracted to shrink the type the compiler must infer)

    @ViewBuilder
    private var stylesSection: some View {
        Section {
            if styles.isEmpty {
                ContentUnavailableView(
                    "No Styles",
                    systemImage: "list.bullet",
                    description: Text("Add styles you use while climbing")
                )
            } else {
                ForEach(styles, id: \.id) { style in
                    MetaRow(name: style.name, isDefault: style.isDefault)
                        .contextMenu {
                            Button {
                                renameDraft = style.name
                                renamingStyle = style
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteStyle(style)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                renameDraft = style.name
                                renamingStyle = style
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)

                            Button(role: .destructive) {
                                deleteStyle(style)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { (idx: IndexSet) in
                    idx.map { styles[$0] }.forEach(deleteStyle(_:))
                }
            }

            Button {
                styleDraft = ""
                showingAddStyle = true
            } label: {
                Label("Add Style", systemImage: "plus")
            }
        } header: {
            Text("Styles")
        }
    }

    @ViewBuilder
    private var daysSection: some View {
        Section {
            if days.isEmpty {
                ContentUnavailableView(
                    "No days",
                    systemImage: "list.bullet",
                    description: Text("Add type of training days")
                )
            } else {
                ForEach(days, id: \.id) { day in
                    DayRow(day: day)
                        .contextMenu {
                            Button {
                                renameDraft = day.name
                                renamingDay = day
                            } label: {
                                Label("Edit", systemImage: "square.and.pencil")
                            }
                            Button(role: .destructive) {
                                safeDeleteDay(day)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                renameDraft = day.name
                                renamingDay = day
                            } label: {
                                Label("Edit", systemImage: "square.and.pencil")
                            }
                            .tint(.blue)

                            Button(role: .destructive) {
                                safeDeleteDay(day)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { (idx: IndexSet) in
                    idx.map { days[$0] }.forEach(safeDeleteDay(_:))
                }
            }

            Button {
                dayDraft = ""
                showingAddDay = true
            } label: {
                Label("Add day", systemImage: "plus")
            }
        } header: {
            Text("Training Days")
        }
    }

    @ViewBuilder
    private var gymsSection: some View {
        Section {
            if gyms.isEmpty {
                ContentUnavailableView(
                    "No Gyms",
                    systemImage: "building.2",
                    description: Text("Add the gyms you visit")
                )
            } else {
                ForEach(gyms, id: \.id) { gym in
                    MetaRow(name: gym.name, isDefault: gym.isDefault)
                        .contextMenu {
                            Button {
                                renameDraft = gym.name
                                renamingGym = gym
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteGym(gym)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                renameDraft = gym.name
                                renamingGym = gym
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)

                            Button(role: .destructive) {
                                deleteGym(gym)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { (idx: IndexSet) in
                    idx.map { gyms[$0] }.forEach(deleteGym(_:))
                }
            }

            Button {
                gymDraft = ""
                showingAddGym = true
            } label: {
                Label("Add Gym", systemImage: "plus")
            }
        } header: {
            Text("Gyms")
        }
    }

    // MARK: - Reusable row (keeps the label pill consistent)
    private struct MetaRow: View {
        let name: String
        let isDefault: Bool

        var body: some View {
            HStack {
                Text(name)
                Spacer()
                if isDefault {
                    Text("Default")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
        }
    }

    private struct DayRow: View {
        @Bindable var day: DayTypeModel

        var body: some View {
            HStack(spacing: 12) {
                Circle()
                    .fill(day.color.gradient)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.name)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: - Deletes
    private func deleteStyle(_ style: ClimbStyle) {
        context.delete(style)
        try? context.save()
    }

    private func safeDeleteDay(_ day: DayTypeModel) {
        // Soft delete: hide instead of removing from the store
        day.isHidden = true
        try? context.save()
    }

    private func deleteGym(_ gym: ClimbGym) {
        context.delete(gym)
        try? context.save()
    }

    private func nonDestructiveResetDayTypes() {
        // Upsert default day types by key (names/colors/order), do not delete existing rows
        seedDayTypes(context)

    }

    // MARK: - Add missing defaults (non-destructive)
    private func addMissingDefaults() {
        // Build case-insensitive sets to avoid duplicates
        let existingStyleNames = Set(styles.map { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        let existingGymNames = Set(gyms.map { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        let existingDayKeys = Set(days.map { $0.key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })

        var insertedCount = 0

        // Insert missing default styles
        for def in ClimbingDefaults.defaultStyles {
            let key = def.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !existingStyleNames.contains(key) {
                context.insert(ClimbStyle(name: def, isDefault: true))
                insertedCount += 1
            }
        }

        // Insert missing default gyms
        for def in ClimbingDefaults.defaultGyms {
            let key = def.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !existingGymNames.contains(key) {
                context.insert(ClimbGym(name: def, isDefault: true))
                insertedCount += 1
            }
        }

        // Insert missing default day types (by key)
        for d in ClimbingDefaults.defaultDayTypes {
            let key = d.key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !existingDayKeys.contains(key) {
                let model = DayTypeModel(key: d.key, name: d.name, order: d.order, colorKey: d.colorKey)
                context.insert(model)
                insertedCount += 1
            }
        }

        do {
            if insertedCount > 0 {
                try context.save()
                resultAlert = InfoAlert(message: "Added \(insertedCount) missing default\(insertedCount == 1 ? "" : "s").")
            } else {
                resultAlert = InfoAlert(message: "All defaults are already present.")
            }
        } catch {
            resultAlert = InfoAlert(message: "Add defaults failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers
    private func findPlanDaysReferencing(dayId: UUID) -> [PlanDay] {
        let fetch = FetchDescriptor<PlanDay>()
        let all = (try? context.fetch(fetch)) ?? []
        return all.filter { $0.type?.id == dayId }
    }
}

#Preview {
    ClimbMetaManagerView()
        .modelContainer(for: [ClimbStyle.self, ClimbGym.self, DayTypeModel.self], inMemory: true)
}

// MARK: - Inline DayColorPickerSheet (kept in this file to satisfy the sheet reference)

private struct DayEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let title: String
    let onSave: (String, String) -> Bool
    
    @State private var name: String
    @State private var colorKey: String
    
    init(title: String, initialName: String, initialColorKey: String, onSave: @escaping (String, String) -> Bool) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _colorKey = State(initialValue: initialColorKey)
    }
    
    private var sortedKeys: [String] {
        let preferred = ["green","blue","indigo","purple","pink","red","orange","yellow","mint","teal","cyan","brown","gray","black","white"]
        let allowed = Array(DayTypeModel.allowedColorKeys)
        let remaining = allowed.filter { !preferred.contains($0) }.sorted()
        return preferred.filter { allowed.contains($0) } + remaining
    }
    
    private func color(for key: String) -> Color {
        DayTypeModel.color(for: key)
    }
    @State private var showingProtectionAlert = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(color(for: colorKey).gradient)
                            .frame(width: 16, height: 16)
                        TextField("Day name", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Day")
                }
                
                Section("Pick a color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                        ForEach(sortedKeys, id: \.self) { key in
                            Button {
                                colorKey = key
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(color(for: key))
                                        .frame(width: 28, height: 28)
                                    if colorKey == key {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.white)
                                            .shadow(radius: 1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(key))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let success = onSave(name, colorKey)
                        if success {
                            dismiss()
                        } else {
                            showingProtectionAlert = true
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Oops..", isPresented: $showingProtectionAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Adding identical default day types is not allowed, you can restore to defaults from the main menu.")
            }
        }
        .presentationDetents([.medium, .large])
    }
}
