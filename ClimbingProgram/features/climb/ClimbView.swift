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
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if climbEntries.isEmpty {
                        // Empty state using consistent design
                        emptyStateCard
                    } else {
                        // Add climb button at the top when there are existing climbs
                        Button {
                            guard isDataReady else { return }
                            showingAddClimb = true
                        } label: {
                            Label("Log a Climb", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(!isDataReady)
                        
                        // List of climbs using card design
                        ForEach(climbEntries) { climb in
                            ClimbRowCard(climb: climb, onDelete: { deleteClimb(climb) })
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Climb")
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
        }
        .opacity(isDataReady ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isDataReady)
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
        CatalogCard(
            title: climb.grade,
            subtitle: climb.dateLogged.formatted(.dateTime.weekday().month().day()),
            tint: climbTypeColor
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Top row: Type, Style, WIP indicator
                HStack {
                    // Climb type badge
                    Text(climb.climbType.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(climbTypeColor.opacity(0.2))
                        .foregroundColor(climbTypeColor)
                        .cornerRadius(4)
                    
                    // Style
                    Text(climb.style)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // WIP indicator
                    if climb.isWorkInProgress {
                        Text("WIP")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.3))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                // Middle row: Location and details
                HStack(spacing: 8) {
                    Text(climb.gym)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    if let angle = climb.angleDegrees {
                        Text("• \(angle)°")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let attempts = climb.attempts, !attempts.isEmpty {
                        Text("• \(attempts) attempts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Notes if available
                if let notes = climb.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    ClimbView()
        .environment(\.isDataReady, true)
        .modelContainer(for: [ClimbEntry.self, ClimbStyle.self, ClimbGym.self])
}
