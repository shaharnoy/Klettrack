//
//  ClimbMetaManagerView.swift
//  Klettrack
//  Created by Shahar Noy on 14.10.25.
//

import SwiftUI
import SwiftData

struct ClimbMetaManagerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    // Fetch all styles and gyms
    @Query(sort: [SortDescriptor(\ClimbStyle.name, order: .forward)]) private var styles: [ClimbStyle]
    @Query(sort: [SortDescriptor(\ClimbGym.name, order: .forward)]) private var gyms: [ClimbGym]
    
    // Add / rename state
    @State private var showingAddStyle = false
    @State private var showingAddGym = false
    @State private var styleDraft = ""
    @State private var gymDraft = ""
    
    @State private var renamingStyle: ClimbStyle? = nil
    @State private var renamingGym: ClimbGym? = nil
    @State private var renameDraft = ""
    
    // Restore/Add defaults state
    @State private var showingRestoreAlert = false
    @State private var restoreResultMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            List {
                // Styles
                Section {
                    if styles.isEmpty {
                        ContentUnavailableView(
                            "No Styles",
                            systemImage: "list.bullet",
                            description: Text("Add styles you use while climbing")
                        )
                    } else {
                        ForEach(styles) { style in
                            HStack {
                                Text(style.name)
                                Spacer()
                                if style.isDefault {
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
                        .onDelete { idx in
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
                
                // Gyms
                Section {
                    if gyms.isEmpty {
                        ContentUnavailableView(
                            "No Gyms",
                            systemImage: "building.2",
                            description: Text("Add the gyms you visit")
                        )
                    } else {
                        ForEach(gyms) { gym in
                            HStack {
                                Text(gym.name)
                                Spacer()
                                if gym.isDefault {
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
                        .onDelete { idx in
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
                        // Full restore (delete + seed)
                        Button(role: .destructive) {
                            showingRestoreAlert = true
                        } label: {
                            Label("Reset back to default values", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            // Add style
            .sheet(isPresented: $showingAddStyle) {
                NameOnlySheet(title: "New Style",
                              placeholder: "e.g. Slab, Power, Coordination…",
                              name: $styleDraft) {
                    let trimmed = styleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let s = ClimbStyle(name: trimmed, isDefault: false)
                    context.insert(s)
                    try? context.save()
                }
            }
            // Add gym
            .sheet(isPresented: $showingAddGym) {
                NameOnlySheet(title: "New Gym",
                              placeholder: "e.g. Ostbloc, Elektra…",
                              name: $gymDraft) {
                    let trimmed = gymDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let g = ClimbGym(name: trimmed, isDefault: false)
                    context.insert(g)
                    try? context.save()
                }
            }
            // Rename style
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
            // Rename gym
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
            // Confirm restore
            .alert("Restore Defaults?", isPresented: $showingRestoreAlert) {
                Button("Restore", role: .destructive) {
                    restoreDefaults()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will replace your current Styles and Gyms with the default values. Your climb logs will not be deleted.")
            }
            // Result message
            .alert(restoreResultMessage ?? "", isPresented: Binding(
                get: { restoreResultMessage != nil },
                set: { if !$0 { restoreResultMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            }
        }
    }
    
    // MARK: - Deletes
    private func deleteStyle(_ style: ClimbStyle) {
        context.delete(style)
        try? context.save()
    }
    
    private func deleteGym(_ gym: ClimbGym) {
        context.delete(gym)
        try? context.save()
    }
    
    // MARK: - Restore defaults (styles + gyms only)
    private func restoreDefaults() {
        do {
            // Remove existing styles and gyms
            try context.delete(model: ClimbStyle.self)
            try context.delete(model: ClimbGym.self)
            try context.save()
            
            // Re-seed using the same seed helper used on first launch
            SeedClimbingData.loadIfNeeded(context)
            restoreResultMessage = "Defaults restored."
        } catch {
            restoreResultMessage = "Restore failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Add missing defaults (non-destructive)
    private func addMissingDefaults() {
        // Build case-insensitive sets of existing names to avoid duplicates
        let existingStyleNames = Set(styles.map { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        let existingGymNames = Set(gyms.map { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        
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
        
        do {
            if insertedCount > 0 {
                try context.save()
                restoreResultMessage = "Added \(insertedCount) missing default\(insertedCount == 1 ? "" : "s")."
            } else {
                restoreResultMessage = "All default styles and gyms are already present."
            }
        } catch {
            restoreResultMessage = "Add defaults failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ClimbMetaManagerView()
        .modelContainer(for: [ClimbStyle.self, ClimbGym.self], inMemory: true)
}
