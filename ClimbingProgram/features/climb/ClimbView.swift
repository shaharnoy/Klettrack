//  ClimbView.swift
//  Klettrack
//  Created by Shahar Noy on 30.08.25.
//

import SwiftUI
import SwiftData

struct ClimbView: View {
    @Environment(\.isDataReady) private var isDataReady
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Query(sort: [SortDescriptor(\ClimbEntry.dateLogged, order: .reverse)]) private var climbEntries: [ClimbEntry]
    @State private var showingAddClimb = false
    @State private var editingClimb: ClimbEntry? = nil
    // NEW: filter state
    @State private var showOnlyWIP = false
    @State private var hidePreviouslyClimbed = false
    
    // NEW: credentials + sync state
    @State private var showingCredentialsSheet = false
    @State private var credsUsername: String = ""
    @State private var credsPassword: String = ""
    @State private var isEditingCredentials = false
    @State private var isSyncing = false
    @State private var syncMessage: String? = nil
    
    // NEW: board picker + pending sync target
    @State private var showingBoardPicker = false
    @State private var pendingBoard: TB2Client.Board? = nil
    
    // NEW: visible Undo banner state
    @State private var showUndoBanner = false
    @State private var undoBannerTask: Task<Void, Never>? = nil
    @State private var undoBannerMessage: String = "Climb deleted"
    
    // Track last-deleted item to validate restore on undo
    @State private var lastDeletedClimbID: UUID? = nil
    @State private var lastDeletedClimbSnapshot: ClimbEntrySnapshot? = nil
    
    // Computed filtered climbs
    private var filteredClimbs: [ClimbEntry] {
        var result = climbEntries
        if showOnlyWIP {
            result = result.filter { $0.isWorkInProgress }
        }
        if hidePreviouslyClimbed {
            result = result.filter { !($0.isPreviouslyClimbed ?? false) }
        }
        return result
    }
    
    // Small helper to avoid heavy inline Binding construction in .alert
    private var isShowingSyncAlert: Binding<Bool> {
        Binding(
            get: { syncMessage != nil },
            set: { if !$0 { syncMessage = nil } }
        )
    }

    // MARK: - Debug helper
    private func debugPtr(_ any: AnyObject?) -> String {
        guard let any else { return "nil" }
        return String(describing: Unmanaged.passUnretained(any).toOpaque())
    }
    private func dumpUndoContext(_ label: String) {
        let envUM = undoManager
        let ctxUM = modelContext.undoManager
        let ctxPtr = debugPtr(modelContext)
        let envPtr = debugPtr(envUM)
        let ctxUMPtr = debugPtr(ctxUM)
        let thread = Thread.isMainThread ? "main" : "background"
        print("UndoCtx[\(label)] thread=\(thread) modelContext=\(ctxPtr) envUM=\(envPtr) ctxUM=\(ctxUMPtr)")
    }
    
    var body: some View {
        NavigationStack {
            if climbEntries.isEmpty { // base dataset empty (not just filters)
                emptyStateCard
            } else {
                List {
                    filterSection
                    addClimbSection
                    climbsSection
                }
                .listStyle(.plain)
                .listRowSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
            }
        }
        .toolbar {
            // SYNC BUTTON (replaces the old "+")
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onSyncTapped()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(!isDataReady || isSyncing)
            }
            // OPTIONS MENU ("…")
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        openCredentialsEditor(for: .tension)
                    } label: {
                        Text("TB2 Login")
                    }
                    Divider()
                    Button {
                        openCredentialsEditor(for: .kilter)
                    } label: {
                        Text("Kilter Login")
                    }
                } label: {
                    Image(systemName: "lock.circle")
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
        // Credentials prompt sheet
        .sheet(isPresented: $showingCredentialsSheet) {
            TB2CredentialsSheet(
                header: (pendingBoard == .kilter) ? "Kilter login details" : "TB2 login details",
                username: $credsUsername,
                password: $credsPassword,
                onSave: {
                    let username = credsUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let password = credsPassword
                    guard !username.isEmpty, !password.isEmpty, let board = pendingBoard else { return }
                    do {
                        try CredentialsStore.saveBoardCredentials(for: board, username: username, password: password)
                        // If we came here via Sync, optionally kick off sync now for the pending board
                        if !isEditingCredentials {
                            Task { await runSyncIfPossible(board: board) }
                        }
                        isEditingCredentials = false
                        pendingBoard = nil
                        showingCredentialsSheet = false
                    } catch {
                        syncMessage = "Failed to save credentials: \(error.localizedDescription)"
                    }
                },
                onCancel: {
                    isEditingCredentials = false
                    pendingBoard = nil
                    showingCredentialsSheet = false
                }
            )
        }
        .alert(syncMessage ?? "", isPresented: isShowingSyncAlert) {
            Button("OK", role: .cancel) { }
        }
        .opacity(isDataReady ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isDataReady)
        .navigationTitle("CLIMB")
        // Optional small overlay to show syncing in progress
        .overlay {
            if isSyncing {
                ProgressView("Syncing…")
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        // Visible Undo banner overlay at the bottom
        .overlay(alignment: .bottom) {
            if showUndoBanner {
                UndoBanner(
                    message: undoBannerMessage,
                    onUndo: { handleUndoTap() },
                    onDismiss: {
                        undoBannerTask?.cancel()
                        showUndoBanner = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        // Board picker dialog
        .confirmationDialog("Sync", isPresented: $showingBoardPicker, titleVisibility: .visible) {
            Button("TB2") { startSync(board: .tension) }
            Button("Kilter") { startSync(board: .kilter) }
            Button("Cancel", role: .cancel) { }
        }
        // Attach the scene's UndoManager to SwiftData so deletes/edits are undoable
        .onAppear {
            dumpUndoContext("onAppear.before")
            // Only set if we have one, or keep whatever the attachUndoManager modifier provided
            let assigned = undoManager ?? UndoManager()
            modelContext.undoManager = assigned
            dumpUndoContext("onAppear.after")
        }
        // Log when isDataReady flips; re-attach if needed
        .onChange(of: isDataReady) { _, newValue in
            dumpUndoContext("isDataReady.change")
            if modelContext.undoManager == nil {
                let assigned = undoManager ?? UndoManager()
                modelContext.undoManager = assigned
                dumpUndoContext("isDataReady.change.afterAssign")
            }
        }
        // Track list changes for context
        .onChange(of: climbEntries.count) { _, newCount in
            dumpUndoContext("entries.count.change")
        }
    }
    
    // MARK: - Sections (split to help the type-checker)
    
    @ViewBuilder
    private var filterSection: some View {
        Section {
            HStack(spacing: 8) {
                filterToggle(isOn: $showOnlyWIP, label: "WIP Only", onSymbol: "flame.fill", offSymbol: "flame")
                filterToggle(isOn: $hidePreviouslyClimbed, label: "Hide Repeats", onSymbol: "eye.slash.fill", offSymbol: "eye.slash")
                Spacer(minLength: 0)
            }
            .font(.caption)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
    
    @ViewBuilder
    private var addClimbSection: some View {
        Section {
            Button {
                guard isDataReady else {
                    print("debug:AddClimb tapped while isDataReady=false — ignoring")
                    return
                }
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
    }
    
    @ViewBuilder
    private var climbsSection: some View {
        Section {
            if filteredClimbs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No climbs match filters")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredClimbs) { climb in
                    ClimbRowCard(climb: climb, onDelete: { deleteClimb(climb) }, onEdit: { editingClimb = climb })
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
    }
    
    // MARK: - Actions
    
    private func onSyncTapped() {
        guard isDataReady else {
            print("debug:Sync tapped while isDataReady=false — ignoring")
            return
        }
        showingBoardPicker = true
    }
    
    private func openCredentialsEditor(for board: TB2Client.Board) {
        // Prefill if saved for that board
        if let creds = CredentialsStore.loadBoardCredentials(for: board) {
            credsUsername = creds.username
            credsPassword = creds.password
        } else {
            credsUsername = ""
            credsPassword = ""
        }
        pendingBoard = board
        isEditingCredentials = true
        showingCredentialsSheet = true
    }
    
    private func startSync(board: TB2Client.Board) {
        if let _ = CredentialsStore.loadBoardCredentials(for: board) {
            Task { await runSyncIfPossible(board: board) }
        } else {
            // Prompt for credentials for this board, then run sync after saving
            credsUsername = ""
            credsPassword = ""
            isEditingCredentials = false
            pendingBoard = board
            showingCredentialsSheet = true
        }
    }
    
    private func runSyncIfPossible(board: TB2Client.Board) async {
        guard let creds = CredentialsStore.loadBoardCredentials(for: board) else {
            syncMessage = "Please enter your \(board == .kilter ? "Kilter" : "Tension") board credentials."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await TB2SyncManager.sync(using: creds, board: board, into: modelContext)
            syncMessage = "Sync completed."
        } catch {
            syncMessage = "Sync failed: \(error.localizedDescription)"
        }
    }
    
    // Filter toggle helper
    @ViewBuilder
    private func filterToggle(isOn: Binding<Bool>, label: String, onSymbol: String, offSymbol: String) -> some View {
        let active = isOn.wrappedValue
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isOn.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: active ? onSymbol : offSymbol)
                Text(label)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? CatalogHue.climbing.color.opacity(0.2) : Color.secondary.opacity(0.12))
            .foregroundColor(active ? CatalogHue.climbing.color : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(active ? "On" : "Off")
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
            dumpUndoContext("deleteClimb.begin")
            // Ensure we have an UndoManager attached
            
            let assigned = undoManager ?? UndoManager()
            modelContext.undoManager = assigned
            dumpUndoContext("deleteClimb.afterAssign")

            modelContext.undoManager?.beginUndoGrouping()
            modelContext.undoManager?.setActionName("Delete Climb")
            
            // Remember which item we deleted (snapshot for robust fallback)
            lastDeletedClimbID = climb.id
            lastDeletedClimbSnapshot = ClimbEntrySnapshot(from: climb)
            // Perform delete
            modelContext.delete(climb)
            modelContext.undoManager?.endUndoGrouping()
            do {
                try modelContext.save()
            } catch {
                print("Save after delete failed: \(error)")
            }
            // Show visible Undo banner for 10 seconds
            showUndoPrompt(message: "Climb deleted")
        }
    }
    
    private func showUndoPrompt(message: String) {
        undoBannerMessage = message
        showUndoBanner = true
        // Cancel any existing timer and schedule a new auto-dismiss in 10 seconds
        undoBannerTask?.cancel()
        undoBannerTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            await MainActor.run {
                if showUndoBanner {
                    showUndoBanner = false
                }
            }
        }
    }

    private func handleUndoTap() {
        dumpUndoContext("onUndo.begin")
        undoBannerTask?.cancel()
        showUndoBanner = false

        // Perform undo via the attached UndoManager
        modelContext.undoManager?.undo()

        // Save after undo
        do {
            try modelContext.save()
        } catch {
            print("Save after undo failed: \(error)")
        }

        // Validate restore; if not restored, fall back to snapshot
        guard let id = lastDeletedClimbID else {
            dumpUndoContext("onUndo.noLastDeletedID")
            return
        }

        do {
            let fetch = FetchDescriptor<ClimbEntry>(predicate: #Predicate { $0.id == id })
            let match = try modelContext.fetch(fetch).first

            if match == nil, let snap = lastDeletedClimbSnapshot {
                let restored = ClimbEntry(
                    id: snap.id,
                    climbType: snap.climbType,
                    grade: snap.grade,
                    angleDegrees: snap.angleDegrees,
                    style: snap.style,
                    attempts: snap.attempts,
                    isWorkInProgress: snap.isWorkInProgress,
                    isPreviouslyClimbed: snap.isPreviouslyClimbed,
                    holdColor: snap.holdColor,
                    gym: snap.gym,
                    notes: snap.notes,
                    dateLogged: snap.dateLogged,
                    tb2ClimbUUID: snap.tb2ClimbUUID
                )
                modelContext.insert(restored)
                try modelContext.save()
            }
        } catch {
            print("Fetch/restore after undo failed: \(error)")
        }

        // Yield one turn to allow @Query to refresh
        Task { @MainActor in
            await Task.yield()
            _ = climbEntries.contains(where: { $0.id == id })
        }

        dumpUndoContext("onUndo.end")
    }
}

// MARK: - Snapshot of a climb for robust undo fallback

private struct ClimbEntrySnapshot {
    let id: UUID
    let climbType: ClimbType
    let grade: String
    let angleDegrees: Int?
    let style: String
    let attempts: String?
    let isWorkInProgress: Bool
    let isPreviouslyClimbed: Bool?
    let holdColor: HoldColor?
    let gym: String
    let notes: String?
    let dateLogged: Date
    let tb2ClimbUUID: String?
    
    init(from c: ClimbEntry) {
        self.id = c.id
        self.climbType = c.climbType
        self.grade = c.grade
        self.angleDegrees = c.angleDegrees
        self.style = c.style
        self.attempts = c.attempts
        self.isWorkInProgress = c.isWorkInProgress
        self.isPreviouslyClimbed = c.isPreviouslyClimbed
        self.holdColor = c.holdColor
        self.gym = c.gym
        self.notes = c.notes
        self.dateLogged = c.dateLogged
        self.tb2ClimbUUID = c.tb2ClimbUUID
    }
}

struct ClimbRowCard: View {
    let climb: ClimbEntry
    let onDelete: () -> Void
    let onEdit: () -> Void
    
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
                        .font(.body)
                        .foregroundColor(.primary)
                }
                // Hold color dot - only show if not "none" and not nil
                if let holdColor = climb.holdColor, holdColor != .none {
                    JugHoldShape()
                        .fill(holdColor.color)
                            .frame(width: 12, height: 12)
                    //border line
                        .overlay(
                            JugHoldShape()
                                .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                        )
                   //other options: EdgeHoldShape() , BlobHoldShape() , HexHoldShape()
                }
                
                Spacer()
                // WIP indicator
                if climb.isWorkInProgress {
                    Text("WIP")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.3))
                        .foregroundColor(.orange)
                        .cornerRadius(3)
                }
                if climb.isPreviouslyClimbed == true {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                  
                // Date
                Text(climb.dateLogged.formatted(.dateTime.year().month().day()))
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            // Bottom row: Style, Gym, and optional details - only show if populated
            let hasStyle = climb.style != "Unknown" && !climb.style.isEmpty
            let hasGym = climb.gym != "Unknown" && !climb.gym.isEmpty
            let hasAngle = climb.angleDegrees != nil
            
            if hasStyle || hasGym || hasAngle {
                HStack(spacing: 4) {
                    if hasStyle {
                        Text(climb.style)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    
                    if hasAngle {
                        if hasStyle {
                            Text("•")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        Text("\(climb.angleDegrees!)°")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    if hasGym {
                        if hasStyle || hasAngle {
                            Text("•")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        Text("\(climb.gym)")
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
        .onTapGesture {
            onEdit()
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
    @State private var selectedDate: Date = Date()
    @State private var isPreviouslyClimbed: Bool = false
    @State private var selectedHoldColor: HoldColor = .none
    
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
                    DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
                    TextField("Grade", text: $grade)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextField("Angle°", text: $angleDegrees)
                        .keyboardType(.numberPad)
                    TextField("Attempts", text: $attempts)
                        .keyboardType(.numberPad)
                    Toggle("WIP?", isOn: $climb.isWorkInProgress)
                    Toggle("Climbed before?", isOn: $isPreviouslyClimbed)
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
        selectedDate = climb.dateLogged
        isPreviouslyClimbed = climb.isPreviouslyClimbed ?? false
        selectedHoldColor = climb.holdColor ?? .none
    }
    
    private func saveChanges() {
        climb.grade = grade.isEmpty ? "Unknown" : grade
        climb.angleDegrees = angleDegrees.isEmpty ? nil : Int(angleDegrees)
        climb.style = selectedStyle.isEmpty ? "Unknown" : selectedStyle
        climb.attempts = attempts.isEmpty ? nil : attempts
        climb.gym = selectedGym.isEmpty ? "Unknown" : selectedGym
        climb.notes = notes.isEmpty ? nil : notes
        climb.dateLogged = selectedDate
        climb.isPreviouslyClimbed = isPreviouslyClimbed
        climb.holdColor = selectedHoldColor
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Save in EditClimbView failed: \(error)")
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


// MARK: - Hold Shapes
/// Rounded hexagon (bolt-on vibe)
struct HexHoldShape: Shape {
    var corner: CGFloat = 0.22
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let cx = r.midX, cy = r.midY
        let R = min(w, h) * 0.5
        let points = (0..<6).map { i -> CGPoint in
            let a = (CGFloat(i) * .pi / 3) - .pi/2
            return CGPoint(x: cx + cos(a) * R, y: cy + sin(a) * R)
        }
        var p = Path()
        p.addRoundedPolygon(points: points, corner: R * corner)
        return p
    }
}

/// Organic blob (resin style)
struct BlobHoldShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: 0.55*w, y: 0.10*h))
        p.addQuadCurve(to: CGPoint(x: 0.95*w, y: 0.45*h),
                       control: CGPoint(x: 0.95*w, y: 0.05*h))
        p.addQuadCurve(to: CGPoint(x: 0.60*w, y: 0.95*h),
                       control: CGPoint(x: 1.00*w, y: 0.90*h))
        p.addQuadCurve(to: CGPoint(x: 0.10*w, y: 0.65*h),
                       control: CGPoint(x: 0.25*w, y: 1.05*h))
        p.addQuadCurve(to: CGPoint(x: 0.55*w, y: 0.10*h),
                       control: CGPoint(x: 0.05*w, y: 0.05*h))
        return p
    }
}

/// Jug-like: rounded triangle with a lip
struct JugHoldShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let a = CGPoint(x: 0.50*w, y: 0.05*h)
        let b = CGPoint(x: 0.95*w, y: 0.75*h)
        let c = CGPoint(x: 0.05*w, y: 0.75*h)
        p.move(to: a)
        p.addQuadCurve(to: b, control: CGPoint(x: 1.00*w, y: 0.20*h))
        p.addQuadCurve(to: c, control: CGPoint(x: 0.80*w, y: 1.05*h))
        p.addQuadCurve(to: a, control: CGPoint(x: 0.00*w, y: 0.20*h))
        // lip
        p.move(to: CGPoint(x: 0.30*w, y: 0.55*h))
        p.addQuadCurve(to: CGPoint(x: 0.70*w, y: 0.55*h),
                       control: CGPoint(x: 0.50*w, y: 0.40*h))
        return p
    }
}

/// Edge / crimp: soft rectangle with a small notch
struct EdgeHoldShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r.insetBy(dx: r.width*0.12, dy: r.height*0.25),
                     cornerSize: CGSize(width: r.width*0.18, height: r.height*0.18))
        // notch
        p.move(to: CGPoint(x: r.minX + r.width*0.25, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width*0.75, y: r.midY))
        return p
    }
}

// MARK: - Utilities

private extension Path {
    mutating func addRoundedPolygon(points: [CGPoint], corner: CGFloat) {
        guard points.count > 2 else { return }
        let n = points.count
        for i in 0..<n {
            let prev = points[(i - 1 + n) % n]
            let curr = points[i]
            let next = points[(i + 1) % n]
            let v1 = CGVector(dx: curr.x - prev.x, dy: curr.y - prev.y)
            let v2 = CGVector(dx: next.x - curr.x, dy: curr.y - next.y)
            let len1 = max(hypot(v1.dx, v1.dy), 0.0001)
            let len2 = max(hypot(v2.dx, v2.dy), 0.0001)
            let inset1 = CGPoint(x: curr.x - v1.dx/len1 * corner, y: curr.y - v1.dy/len1 * corner)
            let inset2 = CGPoint(x: curr.x + v2.dx/len2 * corner, y: curr.y + v1.dy/len2 * corner)
            if i == 0 { move(to: inset1) } else { addLine(to: inset1) }
            addQuadCurve(to: inset2, control: curr)
        }
        closeSubpath()
    }
}

// MARK: - TB2 Credentials Sheet

private struct TB2CredentialsSheet: View {
    let header: String
    @Binding var username: String
    @Binding var password: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(header)
                        .font(.headline)
                }
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    SecureField("Password", text: $password)
                }
            }
            .navigationTitle("Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }
            }
        }
    }
}

// MARK: - Undo banner view

private struct UndoBanner: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void
    // Countdown duration (defaults to 10s to match auto-dismiss)
    var duration: TimeInterval = 10
    
    @State private var progress: CGFloat = 1.0
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button("Undo") {
                onUndo()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        // Embedded countdown progress bar at the bottom of the capsule
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                let barHeight: CGFloat = 3
                // Track
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: max(0, proxy.size.width * progress))
                        .animation(.linear(duration: duration), value: progress)
                }
                .frame(height: barHeight)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .allowsHitTesting(false)
            }
        }
        .shadow(radius: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). Undo")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            // Reset and start the linear countdown animation
            progress = 1.0
            // Deplete to zero over the specified duration
            progress = 0.0
        }
    }
}

#Preview {
    ClimbView()
        .environment(\.isDataReady, true)
        .modelContainer(for: [ClimbEntry.self, ClimbStyle.self, ClimbGym.self])
}

