//
//  MediaManagerView.swift
//  ClimbingProgram
//
//  Created by Shahar Noy on 13.11.25.
//
import SwiftUI
import SwiftData
import Foundation

struct MediaManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ClimbMedia.createdAt, order: .reverse)])
    private var mediaItems: [ClimbMedia]

    @State private var fullScreenMedia: ClimbMedia?
    @State private var editingClimb: ClimbEntry?

    private var groupedByMonth: [(month: Date, items: [ClimbMedia])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: mediaItems) { (media: ClimbMedia) -> Date in
            let comps = calendar.dateComponents([.year, .month], from: media.climb.dateLogged)
            return calendar.date(from: comps) ?? media.climb.dateLogged
        }

        return groups
            .map { (month: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        List {
            ForEach(groupedByMonth, id: \.month) { group in
                Section(header: Text(group.month, format: .dateTime.year().month())) {
                    ForEach(group.items) { media in
                        HStack(alignment: .top, spacing: 12) {
                            //Thumbnail – tap to open full-screen media viewer
                            Button {
                                fullScreenMedia = media
                            } label: {
                                MediaThumbnailView(media: media)
                            }
                            .buttonStyle(.plain)
                            //Climb card – tap/arrow to jump into climb editor
                            Button {
                                editingClimb = media.climb
                            } label: {
                                ClimbRowCardSummary(climb: media.climb)
                            }
                            .buttonStyle(.plain)

                        }
                        .frame(minHeight: 80)
                        .swipeActions {
                            Button(role: .destructive) {
                                delete(media)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Climbing Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $fullScreenMedia) { media in
            MediaFullScreenView(media: media)
        }
        .sheet(item: $editingClimb) { climb in
            // Edit the climb directly using the shared form
            ClimbLogForm(
                title: "Edit Climb",
                initialDate: climb.dateLogged,
                existingClimb: climb,
                onSave: nil
            )
        }
    }

    private func delete(_ media: ClimbMedia) {
        context.delete(media)
        try? context.save()
    }
    
    struct ClimbRowCardSummary: View {
        let climb: ClimbEntry
        @AppStorage(FeatureFlags.showSyncedBoardGradesAsVScale) private var showSyncedBoardGradesAsVScale = false

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
                // Top row: Hold color, Grade • Angle, Date (with 2-digit year)
                HStack(alignment: .center, spacing: 6) {
                    // Hold color dot - only show if not "none" and not nil
                    if let holdColor = climb.holdColor, holdColor != .none {
                        JugHoldShape()
                            .fill(holdColor.color)
                            .frame(width: 12, height: 12)
                            .overlay(
                                JugHoldShape()
                                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                            )
                    }
                    let gradeDisplay = BoardGradeDisplayRules.displayText(
                        grade: climb.grade,
                        feelsLikeGrade: climb.feelsLikeGrade,
                        tb2ClimbUUID: climb.tb2ClimbUUID,
                        kilterClimbUuid: climb.kilterClimbUuid,
                        showSyncedBoardGradesAsVScale: showSyncedBoardGradesAsVScale
                    )

                    if let gradeDisplay {
                        Text(gradeDisplay)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    // Angle
                    if let angle = climb.angleDegrees {
                        if gradeDisplay != nil {
                            Text("•")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(angle)°")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    // Date with 2-digit year (e.g. 25)
                    Text(
                        climb.dateLogged.formatted(
                            .dateTime.year(.twoDigits).month().day()
                        )
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
                let hasStyle = climb.style != "Unknown" && !climb.style.isEmpty
                let hasGym = climb.gym != "Unknown" && !climb.gym.isEmpty
                
                if hasStyle || hasGym {
                    HStack(spacing: 4) {
                        if hasStyle {
                            Text(climb.style)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        if hasGym {
                            if hasStyle {
                                Text("•")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(climb.gym)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }

    }
}
