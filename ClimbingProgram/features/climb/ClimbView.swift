//
//  ClimbView.swift
//  ClimbingProgram
//
//  Created by AI Assistant on 27.08.25.
//

import SwiftUI
import SwiftData

struct ClimbView: View {
    @Environment(\.isDataReady) private var isDataReady
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ClimbEntry.dateLogged, order: .reverse)]) private var climbEntries: [ClimbEntry]
    @State private var showingAddClimb = false
    @State private var editingClimb: ClimbEntry? = nil
    
    var body: some View {
        NavigationStack {
            if climbEntries.isEmpty {
                // Empty state using consistent design
                emptyStateCard
            } else {
                List {
                    // Add climb button at the top when there are existing climbs
                    Section {
                        Button {
                            guard isDataReady else { return }
                            showingAddClimb = true
                        } label: {
                            Label("Log a Climb", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(!isDataReady)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    
                    // List of climbs using card design
                    Section {
                        ForEach(climbEntries) { climb in
                            ClimbRowCard(climb: climb, onDelete: { deleteClimb(climb) })
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteClimb(climb)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    
                                    Button {
                                        editingClimb = climb
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
            }
        }
        .navigationTitle("Climb")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard isDataReady else { return }
                    showingAddClimb = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!isDataReady)
            }
        }
        .sheet(isPresented: $showingAddClimb) {
            AddClimbView()
        }
        .sheet(item: $editingClimb) { climb in
            EditClimbView(climb: climb)
        }
        .opacity(isDataReady ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isDataReady)
    }
    
    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 60))
                .foregroundColor(CatalogHue.climbing.color)
            
            Text("Track your climbing sessions")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showingAddClimb = true }) {
                Label("Add Your First Climb", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(CatalogHue.climbing.color)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
    
    private func deleteClimb(_ climb: ClimbEntry) {
        withAnimation {
            modelContext.delete(climb)
            try? modelContext.save()
        }
    }
}

struct ClimbRowCard: View {
    let climb: ClimbEntry
    let onDelete: () -> Void
    
    private var climbTypeColor: Color {
        switch climb.climbType {
        case .boulder:
            return CatalogHue.bouldering.color
        case .lead:
            return CatalogHue.climbing.color
        }
    }
    
    var body: some View {
        CatalogCard(
            title: climb.grade,
            subtitle: climb.dateLogged.formatted(.dateTime.weekday().month().day()),
            tint: climbTypeColor
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Top row: Type, Style, WIP indicator
                HStack {
                    // Climb type badge
                    Text(climb.climbType.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(climbTypeColor.opacity(0.2))
                        .foregroundColor(climbTypeColor)
                        .cornerRadius(4)
                    
                    // Style
                    Text(climb.style)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // WIP indicator
                    if climb.isWorkInProgress {
                        Text("WIP")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.3))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                // Middle row: Location and details
                HStack(spacing: 8) {
                    Text(climb.gym)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    if let angle = climb.angleDegrees {
                        Text("• \(angle)°")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let attempts = climb.attempts, !attempts.isEmpty {
                        Text("• \(attempts) attempts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Notes if available
                if let notes = climb.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Edit Climb View

struct EditClimbView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var climbStyles: [ClimbStyle]
    @Query private var climbGyms: [ClimbGym]
    
    @Bindable var climb: ClimbEntry
    
    @State private var showingStyleAlert = false
    @State private var showingGymAlert = false
    @State private var newStyleName = ""
    @State private var newGymName = ""
    
    // Local state for editing
    @State private var grade: String = ""
    @State private var angleDegrees: String = ""
    @State private var selectedStyle: String = ""
    @State private var attempts: String = ""
    @State private var selectedGym: String = ""
    @State private var notes: String = ""
    
    // Computed properties to get available options
    private var availableStyles: [String] {
        let seededStyles = ClimbingDefaults.defaultStyles
        let customStyles = climbStyles.map { $0.name }
        return Array(Set(seededStyles + customStyles)).sorted()
    }
    
    private var availableGyms: [String] {
        let seededGyms = ClimbingDefaults.defaultGyms
        let customGyms = climbGyms.map { $0.name }
        return Array(Set(seededGyms + customGyms)).sorted()
    }
    
    private var climbTypeColor: Color {
        switch climb.climbType {
        case .boulder:
            return CatalogHue.bouldering.color
        case .lead:
            return CatalogHue.climbing.color
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Climb Type Picker
                Picker("Type", selection: $climb.climbType) {
                    ForEach(ClimbType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                
                // Style picker with add button
                HStack {
                    Picker("Style", selection: $selectedStyle) {
                        Text("select").tag("")
                        ForEach(availableStyles, id: \.self) { style in
                            Text(style).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Button {
                        showingStyleAlert = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                
                // Gym picker with add button
                HStack {
                    Picker("Gym", selection: $selectedGym) {
                        Text("select").tag("")
                        ForEach(availableGyms, id: \.self) { gym in
                            Text(gym).tag(gym)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Button {
                        showingGymAlert = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                
                Section("Details") {
                    TextField("Grade", text: $grade)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Angle°", text: $angleDegrees)
                        .keyboardType(.numberPad)
                    TextField("Attempts", text: $attempts)
                        .keyboardType(.numberPad)
                    Toggle("WIP?", isOn: $climb.isWorkInProgress)
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("Edit Climb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
            .onAppear {
                initializeFields()
            }
            .alert("Add New Style", isPresented: $showingStyleAlert) {
                TextField("Style name", text: $newStyleName)
                Button("Add") {
                    if !newStyleName.trimmingCharacters(in: .whitespaces).isEmpty {
                        addNewStyle(newStyleName.trimmingCharacters(in: .whitespaces))
                        newStyleName = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newStyleName = ""
                }
            } message: {
                Text("Enter a name for the new climbing style")
            }
            .alert("Add New Gym", isPresented: $showingGymAlert) {
                TextField("Gym name", text: $newGymName)
                Button("Add") {
                    if !newGymName.trimmingCharacters(in: .whitespaces).isEmpty {
                        addNewGym(newGymName.trimmingCharacters(in: .whitespaces))
                        newGymName = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newGymName = ""
                }
            } message: {
                Text("Enter a name for the new gym")
            }
        }
    }
    
    private func initializeFields() {
        grade = climb.grade
        angleDegrees = climb.angleDegrees?.description ?? ""
        selectedStyle = climb.style
        attempts = climb.attempts ?? ""
        selectedGym = climb.gym
        notes = climb.notes ?? ""
    }
    
    private func saveChanges() {
        climb.grade = grade.isEmpty ? "Unknown" : grade
        climb.angleDegrees = angleDegrees.isEmpty ? nil : Int(angleDegrees)
        climb.style = selectedStyle.isEmpty ? "Unknown" : selectedStyle
        climb.attempts = attempts.isEmpty ? nil : attempts
        climb.gym = selectedGym.isEmpty ? "Unknown" : selectedGym
        climb.notes = notes.isEmpty ? nil : notes
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving climb changes: \(error)")
        }
    }
    
    private func addNewStyle(_ styleName: String) {
        let newStyle = ClimbStyle(name: styleName, isDefault: false)
        modelContext.insert(newStyle)
        try? modelContext.save()
        selectedStyle = styleName
    }
    
    private func addNewGym(_ gymName: String) {
        let newGym = ClimbGym(name: gymName, isDefault: false)
        modelContext.insert(newGym)
        try? modelContext.save()
        selectedGym = gymName
    }
}

#Preview {
    ClimbView()
        .environment(\.isDataReady, true)
        .modelContainer(for: [ClimbEntry.self, ClimbStyle.self, ClimbGym.self])
}
