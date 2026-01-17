//  ClimbView.swift
//  Klettrack
//  Created by Shahar Noy on 30.08.25.
//

import SwiftUI
import SwiftData
import PhotosUI
import Photos
import UIKit
import AVKit
import AVFoundation
import StoreKit

struct ClimbView: View {
    @Environment(\.isDataReady) private var isDataReady
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Query(sort: [SortDescriptor(\ClimbEntry.dateLogged, order: .reverse)]) private var climbEntries: [ClimbEntry]
    @State private var showingAddClimb = false
    @State private var editingClimb: ClimbEntry? = nil
    
    // Filters
        @State private var showFilters = false
        @State private var dateRange = DateRange()
        @State private var wipFilter: WipFilter = .all
        @State private var climbTypeFilter: ClimbTypeFilter = .all
        @State private var resendFilter: ResendFilter = .all
        @State private var searchQuery: String = ""
    
    // credentials + sync state
    @State private var showingCredentialsSheet = false
    @State private var credsUsername: String = ""
    @State private var credsPassword: String = ""
    @State private var isEditingCredentials = false
    @State private var isSyncing = false
    @State private var syncMessage: String? = nil
    @State private var showingBoardPicker = false
    @State private var activeBoard: TB2Client.Board? = nil
    @State private var pendingSyncBoard: TB2Client.Board? = nil
    
    // Shared undo components
    @StateObject private var undoSnackbar = UndoSnackbarController()
    @State private var deleteHandler = UndoableDeleteHandler(snapshotter: ClimbEntrySnapshotter())
    
    // In-app review guard (only once per session)
    @State private var hasRequestedReviewThisSession = false
    
    //bulk uploads
    @State private var showingBulkClimbPrompt = false
    @State private var bulkClimbCountText = "4"
    @State private var pendingBulkClimbCount: Int = 1


    // Track successful syncs across launches + pending review trigger
    @AppStorage("klettrack.successfulSyncCount") private var successfulSyncCount = 0
    @AppStorage("klettrack.didRequestReviewAfterSync") private var didRequestReviewAfterSync = false
    @State private var pendingReviewReason: String? = nil
    
    // Computed filtered climbs
    private var filteredClimbs: [ClimbEntry] {
        var result = climbEntries

        // Date range
        if !climbEntries.isEmpty {
            let cal = Calendar.current
            let today = Date()
            let rawStart = dateRange.customStart ?? climbEntries.map(\.dateLogged).min() ?? today
            let rawEnd   = dateRange.customEnd   ?? climbEntries.map(\.dateLogged).max() ?? today
            let start = cal.startOfDay(for: rawStart)
            let end   = cal.date(byAdding: .second, value: -1,
                                 to: cal.date(byAdding: .day, value: 1,
                                              to: cal.startOfDay(for: rawEnd))!)!
            result = result.filter { $0.dateLogged >= start && $0.dateLogged <= end }
        }
        
        // Type: All / Boulder / Sport
        switch climbTypeFilter {
        case .all:
            break
        case .boulder:
            result = result.filter { $0.climbType == .boulder }
        case .sport:
            result = result.filter { $0.climbType == .sport }
        }

        // WIP filter
        switch wipFilter {
        case .all:
            break
        case .yes:
            result = result.filter { $0.isWorkInProgress }
        case .no:
            result = result.filter { !$0.isWorkInProgress }
        }

        // Resend? filter (based on isPreviouslyClimbed)
        switch resendFilter {
        case .all:
            break
        case .resend:
            result = result.filter { ($0.isPreviouslyClimbed ?? false) }
        case .notResend:
            result = result.filter { !($0.isPreviouslyClimbed ?? false) }
        }

        // Free-text search across main string fields
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let q = trimmed.lowercased()
            result = result.filter { matchesSearch($0, query: q) }
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onSyncTapped()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(!isDataReady || isSyncing)
            }

            // Replaces the old lock button
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard isDataReady else { return }
                    bulkClimbCountText = "4"
                    showingBulkClimbPrompt = true
                } label: {
                    Image(systemName: "square.stack.3d.up.fill")
                }
                .disabled(!isDataReady)
                .accessibilityLabel("Bulk add climbs")
            }
        }
        .sheet(isPresented: $showingAddClimb) {
            AddClimbView(bulkCount: pendingBulkClimbCount, onSave: { _ in
                ensureDateRangeInitialized()
                pendingBulkClimbCount = 1 // reset for next time
            })
        }

        .sheet(item: $editingClimb) { climb in
            // Edit the climb directly inside ClimbLogForm
            ClimbLogForm(
                title: "Edit Climb",
                initialDate: climb.dateLogged,
                existingClimb: climb,
                //onSave: nil    // no temp copy; changes are already applied
                onSave: { _ in
                            // recompute date range after editing
                            ensureDateRangeInitialized()
                        }
            )
        }
        // Credentials prompt sheet
        .sheet(item: $activeBoard) { board in
            TB2CredentialsSheet(
                header: (board == .kilter) ? "Kilter login details" : "TB2 login details",
                username: $credsUsername,
                password: $credsPassword,
                onSave: {
                    let username = credsUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let password = credsPassword
                    
                    do {
                        if username.isEmpty && password.isEmpty {
                            // Both empty → treat as "remove credentials"
                            try CredentialsStore.deleteBoardCredentials(for: board)
                        } else {
                            // Non-empty → save/update credentials
                            try CredentialsStore.saveBoardCredentials(
                                for: board,
                                username: username,
                                password: password
                            )
                        }
                        
                        isEditingCredentials = false
                        activeBoard = nil
                    } catch {
                        isEditingCredentials = false
                        activeBoard = nil
                    }
                },
                onCancel: {
                    isEditingCredentials = false
                    activeBoard = nil
                }
            )
        }


        .alert(syncMessage ?? "", isPresented: isShowingSyncAlert) {
            Button("OK", role: .cancel) {
                if let reason = pendingReviewReason {
                    requestReviewIfEligible(reason)
                    pendingReviewReason = nil
                    didRequestReviewAfterSync = true
                }
            }
        }
        .bulkClimbCountPrompt(
            isPresented: $showingBulkClimbPrompt,
            countText: $bulkClimbCountText,
            title: "Bulk add climbs",
            message: "How many climbs to add?"
        ) { count in
            pendingBulkClimbCount = count
            showingAddClimb = true
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
        // Visible Undo banner overlay at the bottom (shared component)
        .overlay(alignment: .bottom) {
            if undoSnackbar.isVisible {
                UndoBanner(
                    message: undoSnackbar.message,
                    duration: 10,
                    onUndo: { undoSnackbar.performUndo() },
                    onDismiss: { undoSnackbar.dismiss() }
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
        // Attach the scene's UndoManager to SwiftData and also to our delete handler
        .onAppear {
            dumpUndoContext("onAppear.before")
            let assigned = undoManager ?? UndoManager()
            modelContext.undoManager = assigned
            deleteHandler.attach(context: modelContext, undoManager: undoManager)
            dumpUndoContext("onAppear.after")
            ensureDateRangeInitialized()
        }
        // Log when isDataReady flips; re-attach if needed
        .onChange(of: isDataReady) { _, _ in
            dumpUndoContext("isDataReady.change")
            if modelContext.undoManager == nil {
                let assigned = undoManager ?? UndoManager()
                modelContext.undoManager = assigned
                deleteHandler.attach(context: modelContext, undoManager: undoManager)
                dumpUndoContext("isDataReady.change.afterAssign")
            }
        }
        // Track list changes for context
        .onChange(of: climbEntries.count) { _, _ in
            dumpUndoContext("entries.count.change")
            ensureDateRangeInitialized()
        }
    }
    
    //Sections
    @ViewBuilder
    private var filterSection: some View {
        Section {
            VStack(spacing: 4) {
                Button {
                        showFilters.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(showFilters ? "Hide filters" : "Show filters")
                        Spacer()
                        if hasActiveFilters {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .font(.subheadline)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                if showFilters {
                    ClimbFilterCard {
                        VStack(spacing: 10) {
                            HStack {
                                HStack {
                                    Text("Dates")
                                    DateRangePicker(range: $dateRange)
                                }
                                ClearAllButton(
                                    action: clearAllFilters,
                                    isEnabled: hasActiveFilters
                                )
                            }

                            HStack {
                                Text("Type")
                                    .font(.callout)
                                    .frame(width: ClimbFilterLayout.labelWidth, alignment: .leading)
                                Picker("", selection: $climbTypeFilter) {
                                    Text("All").tag(ClimbTypeFilter.all)
                                    Text("Boulder").tag(ClimbTypeFilter.boulder)
                                    Text("Sport").tag(ClimbTypeFilter.sport)
                                }
                                .pickerStyle(.segmented)
                            }

                            HStack {
                                Text("WIP?")
                                    .font(.callout)
                                    .frame(width: ClimbFilterLayout.labelWidth, alignment: .leading)
                                Picker("", selection: $wipFilter) {
                                    Text("All").tag(WipFilter.all)
                                    Text("Yes").tag(WipFilter.yes)
                                    Text("No").tag(WipFilter.no)
                                }
                                .pickerStyle(.segmented)
                            }

                            HStack {
                                Text("Resend?")
                                    .font(.callout)
                                    .frame(width: ClimbFilterLayout.labelWidth, alignment: .leading)
                                Picker("", selection: $resendFilter) {
                                    Text("All").tag(ResendFilter.all)
                                    Text("Yes").tag(ResendFilter.resend)
                                    Text("No").tag(ResendFilter.notResend)
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                    TextField("Search anything...", text: $searchQuery)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(.regularMaterial)
                                )
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0)) // match ClimbRowCard
        }
    }




    
    @ViewBuilder
    private var addClimbSection: some View {
        Section {
            Button {
                guard isDataReady else {
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
    
    private func ensureDateRangeInitialized() {
        guard !climbEntries.isEmpty else { return }

        if let minDate = climbEntries.map(\.dateLogged).min(),
           let maxDate = climbEntries.map(\.dateLogged).max() {

            if dateRange.customStart == nil || dateRange.customStart! > minDate {
                dateRange.customStart = minDate
            }

            if dateRange.customEnd == nil || dateRange.customEnd! < maxDate {
                dateRange.customEnd = maxDate
            }
        }
    }
    
    private func openCredentialsEditor(for board: TB2Client.Board) {
        if let creds = CredentialsStore.loadBoardCredentials(for: board) {
            credsUsername = creds.username
            credsPassword = creds.password
        } else {
            credsUsername = ""
            credsPassword = ""
        }
        isEditingCredentials = true
        pendingSyncBoard = nil      // just editing
        activeBoard = board         // drives the sheet
    }


    private func startSync(board: TB2Client.Board) {
        if let _ = CredentialsStore.loadBoardCredentials(for: board) {
            Task { await runSyncIfPossible(board: board) }
        } else {
            // Missing creds → open sheet for this board, then sync after saving
            credsUsername = ""
            credsPassword = ""
            isEditingCredentials = false
            pendingSyncBoard = board
            activeBoard = board      // drives the same sheet
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

            // Count successful syncs (any board). After 3+, arm a one-time review request.
            successfulSyncCount += 1
            if successfulSyncCount >= 3 && !didRequestReviewAfterSync {
                pendingReviewReason = "board_sync"
            }
        } catch {
            syncMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    private func requestReviewIfEligible(_ reason: String) {
        guard !hasRequestedReviewThisSession else { return }
        
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            return
        }
        
        SKStoreReviewController.requestReview(in: scene)
        hasRequestedReviewThisSession = true
    }
    
    // MARK: - Climb list filter helpers
    private enum WipFilter: String, CaseIterable {
        case all = "All"
        case yes = "Yes"
        case no  = "No"
    }

    private enum ResendFilter: String, CaseIterable {
        case all      = "All"
        case resend   = "Resend"
        case notResend = "Not resend"
    }
    
    private enum ClimbTypeFilter: String, CaseIterable {
        case all = "All"
        case boulder = "Boulder"
        case sport = "Sport"
    }

    private enum ClimbFilterLayout {
        static let labelWidth: CGFloat = 64
    }
    // Is any filter active?
    private var hasActiveFilters: Bool {
        dateFilterIsActive
        || climbTypeFilter != .all
        || wipFilter != .all
        || resendFilter != .all
        || !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }



    private func clearAllFilters() {
        dateRange = DateRange()
        climbTypeFilter = .all
        wipFilter = .all
        resendFilter = .all
        searchQuery = ""
        ensureDateRangeInitialized()
    }

    private var dateFilterIsActive: Bool {
        // No climbs → no date filter
        guard !climbEntries.isEmpty,
              let customStart = dateRange.customStart,
              let customEnd = dateRange.customEnd,
              let minDate = climbEntries.map(\.dateLogged).min(),
              let maxDate = climbEntries.map(\.dateLogged).max()
        else {
            return false
        }

        let cal = Calendar.current

        // Consider the date filter "inactive" if it's exactly min → max (by day)
        let sameStartDay = cal.isDate(customStart, inSameDayAs: minDate)
        let sameEndDay   = cal.isDate(customEnd, inSameDayAs: maxDate)

        return !(sameStartDay && sameEndDay)
    }


    // Free-text search across key string fields
    private func matchesSearch(_ climb: ClimbEntry, query: String) -> Bool {
        // `query` is already lowercased
        func contains(_ value: String?) -> Bool {
            guard let value = value, !value.isEmpty else { return false }
            return value.lowercased().contains(query)
        }

        // Add any other string fields you care about here
        return contains(climb.grade)
            || contains(climb.feelsLikeGrade)
            || contains(climb.style)
            || contains(climb.gym)
            || contains(climb.notes)
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
            // Ensure we have an UndoManager attached and connect handler
            let assigned = undoManager ?? UndoManager()
            modelContext.undoManager = assigned
            deleteHandler.attach(context: modelContext, undoManager: undoManager)
            dumpUndoContext("deleteClimb.afterAssign")
            
            // Perform delete via shared handler (cascade will remove ClimbMedia rows)
            deleteHandler.delete(climb, actionName: "Delete Climb")
            
            // Show Undo snackbar using shared controller + banner
            undoSnackbar.show(message: "Climb deleted") {
                // On undo, handler will undo and ensure restore
                deleteHandler.performUndoAndEnsureRestore()
            }
        }
    }

    
    private func handleUndoTap() {
        // If you still call this from anywhere, route through the snackbar controller
        undoSnackbar.performUndo()
    }
}

fileprivate struct ClimbFilterCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(12) // inner padding like other cards
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

// MARK: - Snapshot of a climb for robust undo fallback
// Local snapshot struct no longer needed; handled by ClimbEntrySnapshotter in Shared
struct ClimbRowCard: View {
    let climb: ClimbEntry
    let onDelete: () -> Void
    let onEdit: () -> Void
    
    private var climbTypeColor: Color {
        switch climb.climbType {
        case .boulder:
            return CatalogHue.bouldering.color
        case .sport:
            return CatalogHue.climbing.color
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: Grade, Type, Date, WIP
            HStack(alignment: .center) {
                
                // Climb type badge
                Text(climb.climbType.displayName + (climb.climbType == .sport && climb.ropeClimbType != nil ? " (\(climb.ropeClimbType!.displayName))" : ""))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(climbTypeColor.opacity(0.2))
                    .foregroundColor(climbTypeColor)
                    .cornerRadius(3)
                
                // show grade only if filled, show alternative grade if grade isn't there,
                // show grade& alterntive grade if both exist
                let hasGrade = climb.grade != "Unknown" && !climb.grade.isEmpty
                let hasFeels = (climb.feelsLikeGrade ?? "").isEmpty == false

                if hasGrade || hasFeels {
                    let display: String = {
                        switch (hasGrade, hasFeels) {
                        case (true, true):  return "\(climb.grade) (\(climb.feelsLikeGrade!))"
                        case (true, false): return climb.grade
                        case (false, true): return climb.feelsLikeGrade!   // only feels-like
                        default:            return ""
                        }
                    }()

                    Text(display)
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

// Thumbnail used in EditClimb + MediaManager (small preview)
struct MediaThumbnailView: View {
    let media: ClimbMedia

    private let size: CGFloat = 80
    private let cornerRadius: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail content
            ZStack {
                if let image = loadThumbnailImage() {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .overlay(
                            Image(systemName: media.type == .video ? "video.fill" : "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        )
                }

                // Play overlay for videos
                if media.type == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // Missing badge (top-right)
            if media.isMissingAsset {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.yellow)
                    .padding(4)
                    .background(.black.opacity(0.65))
                    .clipShape(Circle())
                    .offset(x: -4, y: 4)
            }
        }
        .frame(width: size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func loadThumbnailImage() -> UIImage? {
        guard let data = media.thumbnailData else { return nil }
        return UIImage(data: data)
    }
}


// Full-screen media viewer used by EditClimbView
struct MediaFullScreenView: View {
    let media: ClimbMedia
    @Environment(\.dismiss) private var dismiss

    @State private var loadedImage: UIImage?
    @State private var player: AVPlayer?
    @State private var isMissing: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Group {
                if isMissing {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.yellow)
                            .shadow(radius: 4)

                        Text("Media Unavailable")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("""
                    klettrack doesn’t store your media. It only references photos and videos on your device.
                    If the original file was deleted or moved, it can’t be displayed here.
                    """)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 24)
                    }
                    .padding()
                } else {
                    if media.type == .photo {
                        if let image = loadedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    } else {
                        if let player {
                            VideoPlayer(player: player)
                                .ignoresSafeArea()
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .task {
                loadContent()
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding()
        }
    }

    private func loadContent() {
        switch media.type {
        case .photo:
            loadPhoto(id: media.assetLocalIdentifier)
        case .video:
            loadVideo(id: media.assetLocalIdentifier)
        }
    }

    private func fetchAsset(with id: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        return result.firstObject
    }

    private func loadPhoto(id: String) {
        guard let asset = fetchAsset(with: id) else {
            isMissing = true
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        let bounds = UIScreen.main.bounds
        let targetSize = CGSize(
            width: bounds.width * UIScreen.main.scale,
            height: bounds.height * UIScreen.main.scale
        )

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                if let image {
                    self.loadedImage = image
                } else {
                    self.isMissing = true
                }
            }
        }
    }

    private func loadVideo(id: String) {
        guard let asset = fetchAsset(with: id) else {
            isMissing = true
            return
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestPlayerItem(
            forVideo: asset,
            options: options
        ) { playerItem, _ in
            DispatchQueue.main.async {
                if let playerItem {
                    self.player = AVPlayer(playerItem: playerItem)
                } else {
                    self.isMissing = true
                }
            }
        }
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

#Preview {
    ClimbView()
        .environment(\.isDataReady, true)
        .modelContainer(for: [ClimbEntry.self, ClimbStyle.self, ClimbGym.self])
}
