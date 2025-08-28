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
                            Text("Log a Climb")
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
                                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
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
                .listRowSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
            }
        }
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
        .navigationTitle("CLIMB")
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
        VStack(alignment: .leading, spacing: 6) {
            // Top row: Grade, Type, Date, WIP
            HStack(alignment: .center) {
                
                // Climb type badge
                Text(climb.climbType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(climbTypeColor.opacity(0.2))
                    .foregroundColor(climbTypeColor)
                    .cornerRadius(3)
                
                // Grade - only show if not "Unknown"
                if climb.grade != "Unknown" && !climb.grade.isEmpty {
                    Text(climb.grade)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // Date
                Text(climb.dateLogged.formatted(.dateTime.year().month().day()))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // WIP indicator
                if climb.isWorkInProgress {
                    Text("WIP")
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.3))
                        .foregroundColor(.orange)
                        .cornerRadius(3)
                }
            }
            
            // Bottom row: Style, Gym, and optional details - only show if populated
            let hasStyle = climb.style != "Unknown" && !climb.style.isEmpty
            let hasGym = climb.gym != "Unknown" && !climb.gym.isEmpty
            let hasAngle = climb.angleDegrees != nil
            
            if hasStyle || hasGym || hasAngle {
                HStack(spacing: 4) {
                    if hasStyle {
                        Text(climb.style)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    
                    if hasAngle {
                        if hasStyle {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("\(climb.angleDegrees!)°")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if hasGym {
                        if hasStyle || hasAngle {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("@\(climb.gym)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(climbTypeColor.opacity(0.25), lineWidth: 1)
        )
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
