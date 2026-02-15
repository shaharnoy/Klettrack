//
//  ClimbLogForm.swift
//  Klettrack
//  Created by Shahar Noy on 29.08.25.
//

import SwiftUI
import SwiftData
import PhotosUI
import Photos
import AVKit
import AVFoundation
import UIKit

/// A reusable climb logging form that can be used by both the climb module and plans module
struct ClimbLogForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<ClimbStyle> { !$0.isDeleted && $0.isHidden == false },
        sort: [SortDescriptor(\ClimbStyle.name, order: .forward)]
    ) private var climbStyles: [ClimbStyle]
    @Query(
        filter: #Predicate<ClimbGym> { !$0.isDeleted },
        sort: [SortDescriptor(\ClimbGym.name, order: .forward)]
    ) private var climbGyms: [ClimbGym]
    
    // Configuration
    let title: String
    let initialDate: Date
    let onSave: ((ClimbEntry) -> Void)?
    let existingClimb: ClimbEntry?
    let initialNotes: String?
    let bulkCount: Int


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
    @State private var selectedDate: Date
    @State private var isPreviouslyClimbed: Bool = false
    @State private var feelsLikeGrade: String = ""
    @State private var selectedHoldColor: HoldColor = .none
    @State private var didAutoClearGrade = false
    @State private var gradeFocusWasUserInitiated = false

    
    @State private var showingStyleAlert = false
    @State private var showingGymAlert = false
    @State private var newStyleName = ""
    @State private var newGymName = ""
    
    @State private var mediaPickerItems: [PhotosPickerItem] = []
    @State private var mediaPreviews: [ClimbLogMediaPreview] = []
    @State private var isDeletingMedia: Bool = false
    @State private var previewToViewFullScreen: ClimbLogMediaPreview?
    
    @State private var isLoadingMedia: Bool = false
    @State private var isSaving: Bool = false
    
    @State private var showAnglePickerSheet = false
    @State private var showAttemptsPickerSheet = false
    @State private var inputNotes: String = ""
    //ensures we only prefill once (not every re-render)
    @State private var didPrefillNotes = false

    @State private var showingBulkClimbPrompt = false
    @State private var bulkClimbCountText = "4"

    
    // Focus management
    enum Field: Hashable {
        case grade, feelsLikeGrade, angle
    }
    @FocusState private var focusedField: Field?
    
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
        !grade.isEmpty ||
        !angleDegrees.isEmpty ||
        !selectedStyle.isEmpty ||
        !attempts.isEmpty ||
        !selectedGym.isEmpty ||
        !inputNotes.isEmpty ||
        !feelsLikeGrade.isEmpty ||
        isWorkInProgress
    }

    
    init(
        title: String = "Add Climb",
        initialDate: Date = Date(),
        existingClimb: ClimbEntry? = nil,
        initialNotes: String? = nil,
        bulkCount: Int = 1,
        onSave: ((ClimbEntry) -> Void)? = nil
        
    ) {
        self.title = title
        self.initialDate = initialDate
        self.initialNotes = initialNotes
        self.existingClimb = existingClimb
        self.bulkCount = max(1, bulkCount)
        self.onSave = onSave

        if let climb = existingClimb {
            // Prefill from the existing climb (edit mode)
            _selectedClimbType = State(initialValue: climb.climbType)
            _selectedRopeClimbType = State(initialValue: climb.ropeClimbType ?? .lead)
            _grade = State(initialValue: climb.grade == "Unknown" ? "" : climb.grade)
            _feelsLikeGrade = State(initialValue: climb.feelsLikeGrade ?? "")
            _angleDegrees = State(initialValue: climb.angleDegrees.map { String($0) } ?? "")
            _selectedStyle = State(initialValue: climb.style == "Unknown" ? "" : climb.style)
            _attempts = State(initialValue: climb.attempts ?? "")
            _isWorkInProgress = State(initialValue: climb.isWorkInProgress)
            _isPreviouslyClimbed = State(initialValue: climb.isPreviouslyClimbed ?? false)
            _selectedHoldColor = State(initialValue: climb.holdColor ?? .none)
            _selectedGym = State(initialValue: climb.gym == "Unknown" ? "" : climb.gym)
            _inputNotes = State(initialValue: climb.notes ?? "")
            _selectedDate = State(initialValue: climb.dateLogged)

            // NEW: show already attached media as previews
            let previews = climb.media.map { media -> ClimbLogMediaPreview in
                let thumbImage = media.thumbnailData.flatMap { UIImage(data: $0) }
                switch media.type {
                case .photo:
                    return ClimbLogMediaPreview(kind: .existingPhoto(media: media, thumbnail: thumbImage))
                case .video:
                    return ClimbLogMediaPreview(kind: .existingVideo(media: media, thumbnail: thumbImage))
                }
            }
            _mediaPreviews = State(initialValue: previews)
        } else {
            // Add mode
            _selectedDate = State(initialValue: initialDate)
            _mediaPreviews = State(initialValue: [])
        }
    }

    
    private var attemptsIntBinding: Binding<Int> {
        Binding(
            get: { Int(attempts) ?? 1 },
            set: { attempts = String(max(0, $0)) }   // never go below 0
        )
    }
    
    private var angleOptionalBinding: Binding<Int?> {
        Binding<Int?>(
            get: {
                Int(angleDegrees)
            },
            set: { newValue in
                if let newValue = newValue {
                    angleDegrees = String(newValue)
                } else {
                    angleDegrees = ""  // user selected None
                }
            }
        )
    }

    private static let fieldLabelWidth: CGFloat = 80
    private static let fieldControlWidth: CGFloat = 70
    private static let fieldSpacing: CGFloat = 8

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    climbTypePicker
                    gymPicker
                    stylePicker
                    climbDetailsSection
                    holdColorSection
                    mediaSection
                }
                loadingOverlay
            }
            //.navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Only apply session defaults for new climbs, not when editing
                if existingClimb == nil {
                    loadSessionDefaults()
                }
            }
            .onAppear {
                guard !didPrefillNotes else { return }
                didPrefillNotes = true
                if let initialNotes, !initialNotes.isEmpty {
                    inputNotes = initialNotes
                }
            }
            .onChange(of: mediaPickerItems) { _, newItems in
                Task {
                    await loadMediaPreviews(from: newItems)
                }
            }
            .onChange(of: focusedField) { _, newValue in
                if newValue == .grade {
                    if gradeFocusWasUserInitiated && !didAutoClearGrade && !grade.isEmpty {
                        grade = ""
                        didAutoClearGrade = true
                    }
                    gradeFocusWasUserInitiated = false
                } else {
                    didAutoClearGrade = false
                    gradeFocusWasUserInitiated = false
                }
            }
            .fullScreenCover(item: $previewToViewFullScreen) { preview in
                ClimbLogMediaFullScreenView(preview: preview)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if existingClimb != nil {
                        // EDIT MODE: only Cancel (no duplication)
                        Button("Cancel") {
                            dismiss()
                        }
                        .disabled(isSaving)
                    } else {
                        // ADD MODE: overflow menu with Save & duplicate
                        Menu {
                            Button {
                                bulkClimbCountText = "4"
                                showingBulkClimbPrompt = true
                            } label: {
                                Text("Save & Clone")
                            }

                            Divider()

                            Button(role: .destructive) {
                                dismiss()
                            } label: {
                                Text("Cancel")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(isSaving)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveClimb(bulkCount: bulkCount) }
                    }
                    .disabled(!isFormValid || isSaving || isLoadingMedia)
                }
            }
            .applyIf(existingClimb == nil) { view in
                view.bulkClimbCountPrompt(
                    isPresented: $showingBulkClimbPrompt,
                    countText: $bulkClimbCountText,
                    title: "Bulk Log climbs",
                    message: "How many?",
                    confirmTitle: "Save"
                ) { count in
                    Task { await saveClimb(bulkCount: count) }
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

    @ViewBuilder
    private var climbTypePicker: some View {
        Picker("Type", selection: $selectedClimbType) {
            ForEach(ClimbType.allCases, id: \.self) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var gymPicker: some View {
        HStack {
            Picker("Gym", selection: $selectedGym) {
                Text("select...").tag("")
                    .font(.subheadline)
                ForEach(availableGyms, id: \.self) { gym in
                    Text(gym).tag(gym)
                }
            }
            .pickerStyle(.menu)
            .contentShape(Rectangle())
            Button {
                showingGymAlert = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var stylePicker: some View {
        HStack {
            Picker("Style", selection: $selectedStyle) {
                Text("select...").tag("")
                    .font(.subheadline)
                ForEach(availableStyles, id: \.self) { style in
                    Text(style).tag(style)
                }
            }
            .pickerStyle(.menu)
            Button {
                showingStyleAlert = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var climbDetailsSection: some View {
        Section {
            gradeAndFeelsLikeRow
            angleAndAttemptsRow
            wipAndResendRow

            if selectedClimbType == .sport {
                ropeTypePicker
            }

            TextField("Notes (optional)", text: $inputNotes, axis: .vertical)
        }
    }

    @ViewBuilder
    private var gradeAndFeelsLikeRow: some View {
        HStack {
            HStack {
                Text("Grade")
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(width: Self.fieldLabelWidth, alignment: .leading)

                Spacer(minLength: Self.fieldSpacing)

                TextField("V5", text: $grade)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .grade)
                    .submitLabel(.done)
                    .frame(width: Self.fieldControlWidth, alignment: .trailing)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            handleGradeFieldTap()
                        }
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            HStack {
                InfoLabel(
                    text: "My Grade",
                    helpMessage: "Use My Grade for mismatched gym grades, sandbagged climbs, or noting how the climb really felt.",
                    labelWidth: Self.fieldLabelWidth
                )

                Spacer(minLength: Self.fieldSpacing)

                TextField("7a+", text: $feelsLikeGrade)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .feelsLikeGrade)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .frame(width: Self.fieldControlWidth, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var angleAndAttemptsRow: some View {
        HStack {
            HStack {
                Text("Angle")
                    .font(.subheadline)
                    .frame(width: Self.fieldLabelWidth, alignment: .leading)

                Spacer(minLength: Self.fieldSpacing)

                anglePickerButton(controlWidth: Self.fieldControlWidth)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $showAnglePickerSheet) {
                angleSheetContent
            }

            HStack {
                Text("Attempts")
                    .font(.subheadline)
                    .frame(width: Self.fieldLabelWidth, alignment: .leading)

                Spacer(minLength: Self.fieldSpacing)

                attemptsPickerButton(controlWidth: Self.fieldControlWidth)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $showAttemptsPickerSheet) {
                attemptsSheetContent
            }
        }
    }

    @ViewBuilder
    private var wipAndResendRow: some View {
        HStack {
            HStack {
                Text("WIP?")
                    .font(.subheadline)
                    .frame(width: Self.fieldLabelWidth, alignment: .leading)

                Spacer(minLength: Self.fieldSpacing)

                Toggle("", isOn: $isWorkInProgress)
                    .labelsHidden()
                    .frame(width: Self.fieldControlWidth, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text("Resend?")
                    .font(.subheadline)
                    .frame(width: Self.fieldLabelWidth, alignment: .leading)

                Spacer(minLength: Self.fieldSpacing)

                Toggle("", isOn: $isPreviouslyClimbed)
                    .labelsHidden()
                    .frame(width: Self.fieldControlWidth, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var ropeTypePicker: some View {
        Picker("Rope", selection: $selectedRopeClimbType) {
            ForEach(RopeClimbType.allCases, id: \.self) { ropeType in
                Text(ropeType.displayName).tag(ropeType)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var angleSheetContent: some View {
        VStack {
            Text("Angle")
                .font(.headline)
                .padding(.top, 16)

            Picker("Angle", selection: angleOptionalBinding) {
                Text("None").tag(nil as Int?)
                ForEach(Array(stride(from: 0, through: 90, by: 5)), id: \.self) { n in
                    Text("\(n)°").tag(Optional(n))
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxHeight: 250)

            Button("Done") {
                showAnglePickerSheet = false
            }
            .padding(.top, 8)
        }
        .presentationDetents([.fraction(0.4), .medium])
    }

    @ViewBuilder
    private var attemptsSheetContent: some View {
        VStack {
            Text("Attempts")
                .font(.headline)
                .padding(.top, 16)

            Picker("Attempts", selection: attemptsIntBinding) {
                ForEach(1..<100, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxHeight: 250)

            Button("Done") {
                showAttemptsPickerSheet = false
            }
            .padding(.top, 8)
        }
        .presentationDetents([.fraction(0.4), .medium])
    }

    @ViewBuilder
    private var holdColorSection: some View {
        Section("Hold Color") {
            VStack(alignment: .leading, spacing: 4) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                    spacing: 8
                ) {
                    ForEach(HoldColor.allCases, id: \.self) { color in
                        Button {
                            selectedHoldColor = color
                        } label: {
                            HoldColorChip(color: color, isSelected: selectedHoldColor == color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        Section {
            PhotosPicker(
                selection: $mediaPickerItems,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            ) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("Add media")
                    Spacer()
                }
            }
            if !mediaPreviews.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(mediaPreviews) { preview in
                            mediaPreviewTile(preview)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        } header: {
            HStack {
                if !mediaPreviews.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isDeletingMedia.toggle()
                        }
                    } label: {
                        Label(
                            isDeletingMedia ? "Done" : "Delete",
                            systemImage: isDeletingMedia ? "checkmark.circle" : "trash"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isDeletingMedia ? .green : .red)
                }
            }
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if isSaving || isLoadingMedia {
            ZStack {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    ProgressView()
                    Text(isSaving ? "Saving climb…" : "Uploading…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 10)
            }
            .transition(.opacity)
        }
    }

    private func handleGradeFieldTap() {
        gradeFocusWasUserInitiated = true
        if focusedField == .grade {
            if !didAutoClearGrade && !grade.isEmpty {
                grade = ""
                didAutoClearGrade = true
            }
            gradeFocusWasUserInitiated = false
        } else {
            focusedField = .grade
        }
    }

    @ViewBuilder
    private func anglePickerButton(controlWidth: CGFloat) -> some View {
        Button {
            showAnglePickerSheet = true
        } label: {
            HStack(spacing: 4) {
                if angleDegrees.isEmpty {
                    Text("")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(angleDegrees)°")
                        .font(.body)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: controlWidth, alignment: .trailing)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func attemptsPickerButton(controlWidth: CGFloat) -> some View {
        Button {
            showAttemptsPickerSheet = true
        } label: {
            HStack(spacing: 4) {
                Text("\(attemptsIntBinding.wrappedValue)")
                    .font(.body)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: controlWidth, alignment: .trailing)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func mediaPreviewTile(_ preview: ClimbLogMediaPreview) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if isDeletingMedia {
                    deletePreview(preview)
                } else {
                    previewToViewFullScreen = preview
                }
            } label: {
                ClimbLogMediaThumbnailView(preview: preview)
            }
            .buttonStyle(.plain)

            if isDeletingMedia {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .shadow(radius: 2)
                    .offset(x: 4, y: -4)
            }
        }
    }

    @MainActor
    private func saveClimb(bulkCount: Int = 1) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let angleInt      = angleDegrees.isEmpty ? nil : Int(angleDegrees)
        let attemptsText  = String(max(1, attemptsIntBinding.wrappedValue))
        let notesText     = inputNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : inputNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let ropeType: RopeClimbType? = (selectedClimbType == .sport) ? selectedRopeClimbType : nil

        // Decide whether we’re creating a new climb or updating an existing one
        let target: ClimbEntry

        if let existing = existingClimb {
            // EDIT MODE – update the existing climb in place
            existing.climbType           = selectedClimbType
            existing.ropeClimbType       = ropeType
            existing.grade               = grade.isEmpty ? "Unknown" : grade
            existing.feelsLikeGrade      = feelsLikeGrade.isEmpty ? "" : feelsLikeGrade
            existing.angleDegrees        = angleInt
            existing.style               = selectedStyle.isEmpty ? "Unknown" : selectedStyle
            existing.attempts            = attemptsText
            existing.isWorkInProgress    = isWorkInProgress
            existing.isPreviouslyClimbed = isPreviouslyClimbed
            existing.holdColor           = selectedHoldColor
            existing.gym                 = selectedGym.isEmpty ? "Unknown" : selectedGym
            existing.notes               = notesText
            existing.dateLogged          = selectedDate
            SyncLocalMutation.touch(existing)

            target = existing
        } else {
            // NEW CLIMB – create and insert (optionally in bulk)
            func makeClimb() -> ClimbEntry {
                ClimbEntry(
                    climbType: selectedClimbType,
                    ropeClimbType: ropeType,
                    grade: grade.isEmpty ? "Unknown" : grade,
                    feelsLikeGrade: feelsLikeGrade.isEmpty ? "" : feelsLikeGrade,
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
            }

            // Update session memory once
            sessionManager.updateSession(climbType: selectedClimbType, gym: selectedGym)

            // Create the first climb
            let first = makeClimb()
            modelContext.insert(first)
            SyncLocalMutation.touch(first)

            // Create clones (unique UUIDs because each ClimbEntry() generates a new one)
            if bulkCount > 1 {
                for _ in 2...bulkCount {
                    let clone = makeClimb()
                    modelContext.insert(clone)
                    SyncLocalMutation.touch(clone)

                    // Duplicate media picks for each clone (same asset references, new ClimbMedia rows)
                    if !mediaPreviews.isEmpty {
                        for preview in mediaPreviews {
                            switch preview.kind {
                            case .photo(let assetId, let thumbnail):
                                let media = ClimbMedia(
                                    assetLocalIdentifier: assetId,
                                    thumbnailData: thumbnail?.jpegData(compressionQuality: 0.7),
                                    type: .photo,
                                    createdAt: .now,
                                    climb: clone
                                )
                                modelContext.insert(media)
                                SyncLocalMutation.touch(media)

                            case .video(let assetId, let thumbnail):
                                let media = ClimbMedia(
                                    assetLocalIdentifier: assetId,
                                    thumbnailData: thumbnail?.jpegData(compressionQuality: 0.7),
                                    type: .video,
                                    createdAt: .now,
                                    climb: clone
                                )
                                modelContext.insert(media)
                                SyncLocalMutation.touch(media)

                            case .existingPhoto, .existingVideo:
                                // In Add mode these shouldn't appear; ignore if they do.
                                break
                            }
                        }
                    }
                }
            }
            target = first
        }
        // Handle media persistence
        // - existingPhoto / existingVideo: already stored on `target` (we only delete them via deletePreview)
        // - photo / video: new picks, insert as new ClimbMedia rows
        if !mediaPreviews.isEmpty {
            for preview in mediaPreviews {
                switch preview.kind {
                case .photo(let assetId, let thumbnail):
                    let media = ClimbMedia(
                        assetLocalIdentifier: assetId,
                        thumbnailData: thumbnail?.jpegData(compressionQuality: 0.7),
                        type: .photo,
                        createdAt: .now,
                        climb: target
                    )
                    modelContext.insert(media)
                    SyncLocalMutation.touch(media)

                case .video(let assetId, let thumbnail):
                    let media = ClimbMedia(
                        assetLocalIdentifier: assetId,
                        thumbnailData: thumbnail?.jpegData(compressionQuality: 0.7),
                        type: .video,
                        createdAt: .now,
                        climb: target
                    )
                    modelContext.insert(media)
                    SyncLocalMutation.touch(media)

                case .existingPhoto, .existingVideo:
                    // Already stored and linked to `target`; no extra insert
                    break
                }
            }
        }

        do {
            try modelContext.save()
            onSave?(target)
            dismiss()
        } catch {
            print("Error saving climb: \(error)")
        }
    }

    
    struct HoldColorChip: View {
        let color: HoldColor
        let isSelected: Bool

        var body: some View {
            JugHoldShape()
                .fill(color == .none ? Color.gray.opacity(0.3) : color.color)
                .frame(width: 24, height: 24)
                .overlay(
                    JugHoldShape()
                        .stroke(
                            color == .none
                                ? Color.black.opacity(0.8)
                                : Color.white.opacity(0.4),
                            lineWidth: 1.5
                        )
                )
                .overlay(
                    JugHoldShape()
                        .stroke(
                            // ← Key logic
                            isSelected
                                ? (color == .none ? Color.gray : Color.primary)
                                : Color.clear,
                            lineWidth: 2.2
                        )
                )

                // X for "none"
                .overlay(
                    color == .none ?
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.black)
                    : nil
                )
        }
    }

    
    private func addNewStyle(_ styleName: String) {
        let newStyle = ClimbStyle(name: styleName, isDefault: false)
        modelContext.insert(newStyle)
        SyncLocalMutation.touch(newStyle)
        try? modelContext.save()
        selectedStyle = styleName
    }
    
    private func addNewGym(_ gymName: String) {
        let newGym = ClimbGym(name: gymName, isDefault: false)
        modelContext.insert(newGym)
        SyncLocalMutation.touch(newGym)
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

// MARK: - Media for ClimbLogForm
struct ClimbLogMediaPreview: Identifiable {
    enum Kind {
        // New: cases for media already stored on a climb
        case existingPhoto(media: ClimbMedia, thumbnail: UIImage?)
        case existingVideo(media: ClimbMedia, thumbnail: UIImage?)

        // Existing: new media picked in this form
        case photo(assetLocalIdentifier: String, thumbnail: UIImage?)
        case video(assetLocalIdentifier: String, thumbnail: UIImage?)
    }

    let id = UUID()
    var kind: Kind

    var assetLocalIdentifier: String {
        switch kind {
        case .photo(let id, _), .video(let id, _):
            return id
        case .existingPhoto(let media, _), .existingVideo(let media, _):
            return media.assetLocalIdentifier
        }
    }

    var thumbnail: UIImage? {
        switch kind {
        case .photo(_, let image),
             .video(_, let image),
             .existingPhoto(_, let image),
             .existingVideo(_, let image):
            return image
        }
    }

    var isVideo: Bool {
        switch kind {
        case .video, .existingVideo:
            return true
        default:
            return false
        }
    }

    // Helper: underlying existing media (if any)
    var existingMedia: ClimbMedia? {
        switch kind {
        case .existingPhoto(let media, _), .existingVideo(let media, _):
            return media
        default:
            return nil
        }
    }
}



// MARK: - Thumbnail view for previews (no need for warning like in the edit climb since it's only happen on new climb)
struct ClimbLogMediaThumbnailView: View {
    let preview: ClimbLogMediaPreview

    private let size: CGFloat = 80
    private let cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            // Background image or placeholder
            if let image = preview.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()  // fill square, crop excess
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .overlay(
                        Image(systemName: preview.isVideo ? "video" : "photo")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    )
            }

            // Play icon for videos
            if preview.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
        }
        .frame(width: size, height: size)   // strict square
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Full-screen viewer for previews
struct ClimbLogMediaFullScreenView: View {
    let preview: ClimbLogMediaPreview
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
                    switch preview.kind {
                    case .photo(_, _), .existingPhoto(_, _):
                        if let image = loadedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                        
                    case .video(_, _), .existingVideo(_, _):
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
        switch preview.kind {
        case .photo(_, _), .existingPhoto(_, _):
            loadPhoto(id: preview.assetLocalIdentifier)
        case .video(_, _), .existingVideo(_, _):
            loadVideo(id: preview.assetLocalIdentifier)
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

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            Task { @MainActor in
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
            Task { @MainActor in
                if let playerItem {
                    self.player = AVPlayer(playerItem: playerItem)
                } else {
                    self.isMissing = true
                }
            }
        }
    }
}

// MARK: - Media handling helpers for ClimbLogForm

extension ClimbLogForm {
    fileprivate func deletePreview(_ preview: ClimbLogMediaPreview) {
        // If this preview represents an existing ClimbMedia, delete it from the store
        if let existing = preview.existingMedia {
            SyncLocalMutation.softDelete(existing)
        }
        mediaPreviews.removeAll { $0.id == preview.id }
    }

    @MainActor
    fileprivate func loadMediaPreviews(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        isLoadingMedia = true
        defer {
            isLoadingMedia = false
            mediaPickerItems.removeAll()
        }

        let imageManager = PHCachingImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .opportunistic
        requestOptions.resizeMode = .fast
        requestOptions.isSynchronous = true
        requestOptions.isNetworkAccessAllowed = true

        let targetSize = CGSize(width: 200, height: 200)

        for (index, item) in items.enumerated() {
            guard let id = item.itemIdentifier else {
                print("PhotosPickerItem \(index + 1) has no itemIdentifier")
                continue
            }

            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard let asset = fetchResult.firstObject else {
                print("No PHAsset found for identifier \(id)")
                continue
            }

            var thumb: UIImage?
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: requestOptions
            ) { image, _ in
                thumb = image
            }

            switch asset.mediaType {
            case .video:
                mediaPreviews.append(
                    ClimbLogMediaPreview(kind: .video(assetLocalIdentifier: id, thumbnail: thumb))
                )
            default:
                mediaPreviews.append(
                    ClimbLogMediaPreview(kind: .photo(assetLocalIdentifier: id, thumbnail: thumb))
                )
            }
        }
    }
}

extension View {
    @ViewBuilder
    func applyIf<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
