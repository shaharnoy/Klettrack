//
//  ClimbLogForm.swift
//  Klettrack
//  Created by Shahar Noy on 29.08.25.
//

import SwiftUI
import SwiftData
import PhotosUI
import AVKit
import AVFoundation
import UIKit

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
    
    @State private var mediaPickerItems: [PhotosPickerItem] = []
    @State private var mediaPreviews: [ClimbLogMediaPreview] = []
    @State private var isDeletingMedia: Bool = false
    @State private var previewToViewFullScreen: ClimbLogMediaPreview?
    
    @State private var isLoadingMedia: Bool = false
    @State private var isSaving: Bool = false
    
    // Focus management
    enum Field: Hashable {
        case grade, angle
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
    
    private var attemptsIntBinding: Binding<Int> {
        Binding(
            get: { Int(attempts) ?? 1 },
            set: { attempts = String(max(0, $0)) }   // never go below 0
        )
    }
    
    var body: some View {
        NavigationStack {
         ZStack {
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
                    LabeledContent("Grade") {
                        TextField("e.g. 7a/V6", text: $grade, prompt: nil) //
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .focused($focusedField, equals: .grade)
                            .submitLabel(.done)
                            .onSubmit {
                                focusedField = .angle
                            }
                    }
                    LabeledContent("Angle") {
                        HStack(spacing: 6) {
                            TextField("0", text: $angleDegrees, prompt: nil)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .focused($focusedField, equals: .angle)
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        if focusedField == .angle {
                                            Spacer()
                                            Button {
                                                focusedField = nil
                                            } label: {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(.primary)
                                                    .frame(width: 28, height: 28)
                                                    .background(Color.accentColor.opacity(0.15))
                                                    .clipShape(Circle())
                                                    .overlay(
                                                        Circle()
                                                            .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
                                                    )
                                                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                        }
                    }
                    Stepper(value: attemptsIntBinding, in: 1...9999) {
                        Text("Attempts: \(attemptsIntBinding.wrappedValue)")
                    }
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
                //Media picker + strip
                Section {
                    PhotosPicker(
                        selection: $mediaPickerItems,
                        maxSelectionCount: 10,
                        matching: .any(of: [.images, .videos])
                    ) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Add media")
                            Spacer()
                        }
                    }
                    
                    if mediaPreviews.isEmpty {
                        Text("No media attached")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(mediaPreviews) { preview in
                                    ZStack(alignment: .topTrailing) {
                                        ClimbLogMediaThumbnailView(preview: preview)
                                            .onTapGesture {
                                                if isDeletingMedia {
                                                    deletePreview(preview)
                                                } else {
                                                    previewToViewFullScreen = preview
                                                }
                                            }
                                        
                                        if isDeletingMedia {
                                            Button {
                                                deletePreview(preview)
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .red)
                                                    .shadow(radius: 2)
                                            }
                                            .buttonStyle(.plain)
                                            .offset(x: 4, y: -4)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    HStack {
                        Text("Media")
                        Spacer()
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadSessionDefaults()
            }
            .onChange(of: mediaPickerItems) { _, newItems in
                Task {
                    await loadMediaPreviews(from: newItems)
                }
            }
            .fullScreenCover(item: $previewToViewFullScreen) { preview in
                ClimbLogMediaFullScreenView(preview: preview)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveClimb()
                        }
                    }
                    .disabled(!isFormValid || isSaving || isLoadingMedia)
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
    
    @MainActor
    private func saveClimb() async {
        guard !isSaving else { return }

        isSaving = true
        defer { isSaving = false }

        let angleInt = angleDegrees.isEmpty ? nil : Int(angleDegrees)
        let attemptsText = attempts.isEmpty ? nil : attempts
        let notesText = notes.isEmpty ? nil : notes
        let ropeType: RopeClimbType? = (selectedClimbType == .sport) ? selectedRopeClimbType : nil

        let climb = ClimbEntry(
            climbType: selectedClimbType,
            ropeClimbType: ropeType,
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

        // Persist media previews as ClimbMedia linked to this climb
        if !mediaPreviews.isEmpty {
            let fm = FileManager.default
            if let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                for preview in mediaPreviews {
                    switch preview.kind {
                    case .photo(let data):
                        let filename = "climb-\(climb.id)-\(UUID().uuidString).jpg"
                        let url = dir.appendingPathComponent(filename)
                        do {
                            try data.write(to: url)
                            let media = ClimbMedia(
                                fileName: filename,
                                thumbnailFileName: nil,
                                type: .photo,
                                createdAt: .now,
                                climb: climb
                            )
                            modelContext.insert(media)
                        } catch {
                            print("Error writing photo media: \(error)")
                        }

                    case .video(let data, _):
                        let filename = "climb-\(climb.id)-\(UUID().uuidString).mov"
                        let url = dir.appendingPathComponent(filename)
                        do {
                            try data.write(to: url)
                            var thumbName: String? = nil

                            if let thumbnail = generateVideoThumbnail(for: url),
                               let thumbData = thumbnail.jpegData(compressionQuality: 0.8) {
                                let tn = filename.replacingOccurrences(of: ".mov", with: "-thumb.jpg")
                                let thumbURL = dir.appendingPathComponent(tn)
                                do {
                                    try thumbData.write(to: thumbURL)
                                    thumbName = tn
                                } catch {
                                    print("Error writing video thumbnail: \(error)")
                                }
                            }

                            let media = ClimbMedia(
                                fileName: filename,
                                thumbnailFileName: thumbName,
                                type: .video,
                                createdAt: .now,
                                climb: climb
                            )
                            modelContext.insert(media)
                        } catch {
                            print("Error writing video media: \(error)")
                        }
                    }
                }
            }
        }

        do {
            try modelContext.save()
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

// MARK: - Media for ClimbLogForm
struct ClimbLogMediaPreview: Identifiable {
    enum Kind {
        case photo(Data)
        case video(data: Data, thumbnail: UIImage?)
    }

    let id = UUID()
    var kind: Kind
}

// MARK: - Thumbnail view for previews
struct ClimbLogMediaThumbnailView: View {
    let preview: ClimbLogMediaPreview

    private let size: CGFloat = 80
    private let cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            // Background image or placeholder
            if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()  // fill square, crop excess
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.secondary.opacity(0.05))
                    )
                    .overlay(
                        Image(systemName: isVideo ? "video.fill" : "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            }

            // Play icon for videos
            if isVideo {
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

    private var isVideo: Bool {
        if case .video = preview.kind { return true }
        return false
    }

    private func loadImage() -> UIImage? {
        switch preview.kind {
        case .photo(let data):
            return UIImage(data: data)
        case .video(_, let thumbnail):
            return thumbnail
        }
    }
}


// MARK: - Full-screen viewer for previews
struct ClimbLogMediaFullScreenView: View {
    let preview: ClimbLogMediaPreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

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

    @ViewBuilder
    private var content: some View {
        switch preview.kind {
        case .photo(let data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("Unable to load image")
                    .foregroundStyle(.white)
            }

        case .video(let data, _):
            if let url = makeTempURL(for: data) {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            } else {
                Text("Unable to load video")
                    .foregroundStyle(.white)
            }
        }
    }

    private func makeTempURL(for data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("climblog-preview-\(preview.id).mov")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("Failed to write temp video file: \(error)")
            return nil
        }
    }
}

// MARK: - Media handling helpers for ClimbLogForm

extension ClimbLogForm {
    fileprivate func deletePreview(_ preview: ClimbLogMediaPreview) {
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

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory

        for (index, item) in items.enumerated() {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    if UIImage(data: data) != nil {
                        // Photo
                        mediaPreviews.append(
                            ClimbLogMediaPreview(kind: .photo(data))
                        )
                    } else {
                        // Video – generate a temporary thumbnail
                        var thumbnail: UIImage? = nil
                        let tempURL = tempDir.appendingPathComponent("climblog-preview-\(UUID().uuidString).mov")
                        do {
                            try data.write(to: tempURL, options: .atomic)
                            thumbnail = generateVideoThumbnail(for: tempURL)
                            try? fm.removeItem(at: tempURL)
                        } catch {
                            print("Error writing temp video file for preview \(index + 1): \(error)")
                        }

                        mediaPreviews.append(
                            ClimbLogMediaPreview(kind: .video(data: data, thumbnail: thumbnail))
                        )
                    }
                } else {
                    print("loadTransferable returned nil for item \(index + 1)")
                }
            } catch {
                print("Error loading media data for item \(index + 1): \(error)")
            }
        }
    }




    fileprivate func generateVideoThumbnail(for url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)

        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Failed to generate video thumbnail: \(error)")
            return nil
        }
    }
}
