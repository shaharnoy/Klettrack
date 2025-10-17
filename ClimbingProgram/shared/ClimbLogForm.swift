//
//  ClimbLogForm.swift
//  Klettrack
//  Created by Shahar Noy on 29.08.25.
//

import SwiftUI
import SwiftData

/// A reusable climb logging form that can be used by both the climb module and plans module
struct ClimbLogForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var climbStyles: [ClimbStyle]
    @Query private var climbGyms: [ClimbGym]
    
    // Configuration
    let title: String
    let initialDate: Date
    let onSave: ((ClimbEntry) -> Void)?
    
    // Session manager for remembering climb type and gym
    @State private var sessionManager = ClimbSessionManager.shared
    
    @State private var selectedClimbType: ClimbType = .boulder
    @State private var selectedRopeClimbType: RopeClimbType = .lead
    @State private var grade: String = ""
    @State private var angleDegrees: String = ""
    @State private var selectedStyle: String = ""
    @State private var attempts: String = ""
    @State private var isWorkInProgress: Bool = false
    @State private var selectedGym: String = ""
    @State private var notes: String = ""
    @State private var selectedDate: Date
    @State private var isPreviouslyClimbed: Bool = false
    @State private var selectedHoldColor: HoldColor = .none
    
    @State private var showingStyleAlert = false
    @State private var showingGymAlert = false
    @State private var newStyleName = ""
    @State private var newGymName = ""
    
    // Computed properties to get available options
    private var availableStyles: [String] {
        // Prefer live SwiftData; only fall back to defaults if none exist in the store
        let live = climbStyles.map { $0.name }
        if !live.isEmpty { return Array(Set(live)).sorted() }
        return Array(Set(ClimbingDefaults.defaultStyles)).sorted()
    }
    
    private var availableGyms: [String] {
        // Prefer live SwiftData; only fall back to defaults if none exist in the store
        let live = climbGyms.map { $0.name }
        if !live.isEmpty { return Array(Set(live)).sorted() }
        return Array(Set(ClimbingDefaults.defaultGyms)).sorted()
    }
    
    private var climbTypeColor: Color {
        switch selectedClimbType {
        case .boulder:
            return CatalogHue.bouldering.color
        case .sport:
            return CatalogHue.climbing.color
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
    
    init(title: String = "Add Climb", initialDate: Date = Date(), onSave: ((ClimbEntry) -> Void)? = nil) {
        self.title = title
        self.initialDate = initialDate
        self.onSave = onSave
        self._selectedDate = State(initialValue: initialDate)
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
                    DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
                    TextField("Grade", text: $grade)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Angle°", text: $angleDegrees)
                        .keyboardType(.numberPad)
                    TextField("Attempts", text: $attempts)
                        .keyboardType(.numberPad)
                    Toggle("WIP?", isOn: $isWorkInProgress)
                    Toggle("Previously climbed?", isOn: $isPreviouslyClimbed)
                    //Rope type picker, shown only for Sport climbs
                    if selectedClimbType == .sport {
                        Picker("Rope", selection: $selectedRopeClimbType) {
                            ForEach(RopeClimbType.allCases, id: \.self) { ropeType in
                                Text(ropeType.displayName).tag(ropeType)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    TextField("Notes", text: $notes)
                }
                // Hold color picker
                Section("Hold Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(HoldColor.allCases, id: \.self) { color in
                            Button {
                                selectedHoldColor = color
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(color == .none ? Color.gray.opacity(0.3) : color.color)
                                        .frame(width: 24, height: 24)
                                        // Always show a thin border (block circle)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.secondary.opacity(0.4), lineWidth: 2)
                                        )
                                        // Extra border if selected
                                        .overlay(
                                            Circle()
                                                .stroke(selectedHoldColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                        )
                                        .overlay(
                                            // Special handling for "none" option
                                            color == .none ?
                                            Image(systemName: "xmark")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            : nil
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadSessionDefaults()
            }
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
    
    private func saveClimb() {
        let angleInt = angleDegrees.isEmpty ? nil : Int(angleDegrees)
        let attemptsText = attempts.isEmpty ? nil : attempts
        let notesText = notes.isEmpty ? nil : notes
        let ropeType: RopeClimbType? = (selectedClimbType == .sport) ? selectedRopeClimbType : nil
        
        let climb = ClimbEntry(
            climbType: selectedClimbType,
            
            grade: grade.isEmpty ? "Unknown" : grade,
            angleDegrees: angleInt,
            style: selectedStyle.isEmpty ? "Unknown" : selectedStyle,
            attempts: attemptsText,
            isWorkInProgress: isWorkInProgress,
            isPreviouslyClimbed: isPreviouslyClimbed ? true : false,
            holdColor: selectedHoldColor,
            gym: selectedGym.isEmpty ? "Unknown" : selectedGym,
            notes: notesText,
            dateLogged: selectedDate
        )
        
        // Update session memory with this climb's info
        sessionManager.updateSession(climbType: selectedClimbType, gym: selectedGym)
        
        modelContext.insert(climb)
        
        do {
            try modelContext.save()
            
            // Call the custom onSave handler if provided (for plan integration)
            onSave?(climb)
            
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
    
    /// Load session defaults when the view appears
    private func loadSessionDefaults() {
        // First try to initialize from today's climbs if no session exists
        sessionManager.initializeFromTodaysClimbs(modelContext: modelContext)
        
        // Then load the session defaults
        if let sessionClimbType = sessionManager.getSessionClimbType(from: modelContext) {
            selectedClimbType = sessionClimbType
        }
        
        if let sessionGym = sessionManager.getSessionGym(from: modelContext) {
            selectedGym = sessionGym
        }
    }
    
    /// Reset fields to default values when session is cleared
    private func resetToDefaults() {
        selectedClimbType = .boulder
        selectedGym = ""
        selectedDate = Date()
    }
}

