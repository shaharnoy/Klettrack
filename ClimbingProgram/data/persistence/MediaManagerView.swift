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
                        NavigationLink {
                            // Jump into the climb editor / detail so user can see full context
                            EditClimbView(climb: media.climb)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                MediaThumbnailView(media: media)   // uses its internal 80×80

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(media.climb.grade) • \(media.climb.style)")
                                        .font(.subheadline)
                                    Text(media.climb.gym)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Text(media.climb.dateLogged, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                Image(systemName: media.type == .photo ? "photo" : "video.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 80)
                        }
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
        .navigationTitle("Media Manager")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func delete(_ media: ClimbMedia) {
        context.delete(media)
        try? context.save()
    }
}


