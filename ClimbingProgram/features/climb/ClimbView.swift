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
    @Query private var climbEntries: [ClimbEntry]
    @State private var showingAddClimb = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if climbEntries.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "mountain.2.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        Text("Climb")
                            .font(.largeTitle.bold())
                        
                        Text("Start tracking your climbing sessions")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Button(action: { showingAddClimb = true }) {
                            Label("Add New Climb", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
                } else {
                    // List of climbs
                    List {
                        ForEach(climbEntries.sorted(by: { $0.dateLogged > $1.dateLogged })) { climb in
                            ClimbRowView(climb: climb)
                        }
                        .onDelete(perform: deleteClimbs)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Climb")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddClimb = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddClimb) {
                AddClimbView()
            }
        }
        .opacity(isDataReady ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isDataReady)
    }
    
    private func deleteClimbs(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let sortedClimbs = climbEntries.sorted(by: { $0.dateLogged > $1.dateLogged })
                modelContext.delete(sortedClimbs[index])
            }
        }
    }
}

struct ClimbRowView: View {
    let climb: ClimbEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Climb type indicator
                Text(climb.climbType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(climb.climbType == .boulder ? Color.orange : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                
                Spacer()
                
                // Date
                Text(climb.dateLogged, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                // Grade
                Text(climb.grade)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Style
                Text(climb.style)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // WIP indicator
                if climb.isWorkInProgress {
                    Text("WIP")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(4)
                }
            }
            
            HStack {
                // Gym
                Text(climb.gym)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
            }
            
            if let notes = climb.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ClimbView()
        .environment(\.isDataReady, true)
        .modelContainer(for: [ClimbEntry.self, ClimbStyle.self, ClimbGym.self])
}
