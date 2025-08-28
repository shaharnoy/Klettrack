//
//  AddClimbView.swift
//  ClimbingProgram
//
//  Created by AI Assistant on 28.08.25.
//

import SwiftUI
import SwiftData

struct AddClimbView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var climbStyles: [ClimbStyle]
    @Query private var climbGyms: [ClimbGym]
    
    @State private var selectedClimbType: ClimbType = .boulder
    @State private var grade: String = ""
    @State private var angleDegrees: String = ""
    @State private var selectedStyle: String = ""
    @State private var attempts: String = ""
    @State private var isWorkInProgress: Bool = false
    @State private var selectedGym: String = ""
    @State private var notes: String = ""
    
    @State private var showingStylePicker = false
    @State private var showingGymPicker = false
    @State private var newStyleName = ""
    @State private var newGymName = ""
    
    // Computed properties to get available options
    private var availableStyles: [String] {
        // Combine seeded styles with custom styles
        let seededStyles = ClimbingDefaults.defaultStyles
        let customStyles = climbStyles.map { $0.name }
        return Array(Set(seededStyles + customStyles)).sorted()
    }
    
    private var availableGyms: [String] {
        // Combine seeded gyms with custom gyms
        let seededGyms = ClimbingDefaults.defaultGyms
        let customGyms = climbGyms.map { $0.name }
        return Array(Set(seededGyms + customGyms)).sorted()
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Climb Type") {
                    Picker("Type", selection: $selectedClimbType) {
                        ForEach(ClimbType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Details") {
                    HStack {
                        Text("Grade")
                        Spacer()
                        TextField("e.g., 6a, V4, 8-, 10+", text: $grade)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 150)
                    }
                    
                    HStack {
                        Text("Angle (degrees)")
                        Spacer()
                        TextField("Optional", text: $angleDegrees)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(maxWidth: 100)
                    }
                    
                    HStack {
                        Text("Style")
                        Spacer()
                        Button(selectedStyle.isEmpty ? "Select Style" : selectedStyle) {
                            showingStylePicker = true
                        }
                        .foregroundColor(selectedStyle.isEmpty ? .secondary : .primary)
                    }
                    
                    HStack {
                        Text("Attempts")
                        Spacer()
                        TextField("Optional", text: $attempts)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                    }
                    
                    Toggle("Work in Progress", isOn: $isWorkInProgress)
                    
                    HStack {
                        Text("Gym")
                        Spacer()
                        Button(selectedGym.isEmpty ? "Select Gym" : selectedGym) {
                            showingGymPicker = true
                        }
                        .foregroundColor(selectedGym.isEmpty ? .secondary : .primary)
                    }
                }
                
                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Climb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveClimb()
                    }
                    .disabled(!isFormValid)
                }
            }
            .sheet(isPresented: $showingStylePicker) {
                StylePickerView(
                    selectedStyle: $selectedStyle,
                    availableStyles: availableStyles,
                    onAddNew: addNewStyle
                )
            }
            .sheet(isPresented: $showingGymPicker) {
                GymPickerView(
                    selectedGym: $selectedGym,
                    availableGyms: availableGyms,
                    onAddNew: addNewGym
                )
            }
        }
    }
    
    private var isFormValid: Bool {
        // Allow saving if any field has input (no mandatory fields)
        !grade.isEmpty ||
        !angleDegrees.isEmpty ||
        !selectedStyle.isEmpty ||
        !attempts.isEmpty ||
        !selectedGym.isEmpty ||
        !notes.isEmpty ||
        isWorkInProgress
    }
    
    private func saveClimb() {
        let angleInt = angleDegrees.isEmpty ? nil : Int(angleDegrees)
        let attemptsText = attempts.isEmpty ? nil : attempts
        let notesText = notes.isEmpty ? nil : notes
        
        let climb = ClimbEntry(
            climbType: selectedClimbType,
            grade: grade.isEmpty ? "Unknown" : grade,
            angleDegrees: angleInt,
            style: selectedStyle.isEmpty ? "Unknown" : selectedStyle,
            attempts: attemptsText,
            isWorkInProgress: isWorkInProgress,
            gym: selectedGym.isEmpty ? "Unknown" : selectedGym,
            notes: notesText
        )
        
        modelContext.insert(climb)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving climb: \(error)")
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

struct StylePickerView: View {
    @Binding var selectedStyle: String
    let availableStyles: [String]
    let onAddNew: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newStyleName = ""
    @State private var showingAddNew = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(availableStyles, id: \.self) { style in
                    Button(style) {
                        selectedStyle = style
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
                
                Button("Add New Style...") {
                    showingAddNew = true
                }
                .foregroundColor(.blue)
            }
            .navigationTitle("Select Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Add New Style", isPresented: $showingAddNew) {
                TextField("Style name", text: $newStyleName)
                Button("Add") {
                    if !newStyleName.isEmpty {
                        onAddNew(newStyleName)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct GymPickerView: View {
    @Binding var selectedGym: String
    let availableGyms: [String]
    let onAddNew: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newGymName = ""
    @State private var showingAddNew = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(availableGyms, id: \.self) { gym in
                    Button(gym) {
                        selectedGym = gym
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
                
                Button("Add New Gym...") {
                    showingAddNew = true
                }
                .foregroundColor(.blue)
            }
            .navigationTitle("Select Gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Add New Gym", isPresented: $showingAddNew) {
                TextField("Gym name", text: $newGymName)
                Button("Add") {
                    if !newGymName.isEmpty {
                        onAddNew(newGymName)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

#Preview {
    AddClimbView()
        .modelContainer(for: [ClimbEntry.self, ClimbStyle.self, ClimbGym.self])
}
