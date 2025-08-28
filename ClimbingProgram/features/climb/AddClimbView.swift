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
    
    @State private var showingStyleAlert = false
    @State private var showingGymAlert = false
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
    
    private var climbTypeColor: Color {
        switch selectedClimbType {
        case .boulder:
            return CatalogHue.bouldering.color
        case .lead:
            return CatalogHue.climbing.color
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Climb Type Picker - changed to dropdown menu
                Picker("Type", selection: $selectedClimbType) {
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
                    Toggle("WIP?", isOn: $isWorkInProgress)
                    TextField("Notes", text: $notes)
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

// MARK: - Modern Input Components

struct ModernInputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    
    init(title: String, placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .keyboardType(keyboardType)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }
}

struct ModernPickerField: View {
    let title: String
    let selection: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Button(action: action) {
                HStack {
                    Text(selection)
                        .foregroundColor(isSelected ? .primary : .secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
}

#Preview {
    AddClimbView()
        .modelContainer(for: [ClimbEntry.self, ClimbStyle.self, ClimbGym.self])
}
