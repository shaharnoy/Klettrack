//
//  TimerTemplatesListView.swift
//  Klettrack
//  Created by Shahar Noy on 25.08.25.
//

import SwiftUI
import SwiftData

// MARK: - Timer Templates Management View
struct TimerTemplatesListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isDataReady) private var isDataReady

    @Query(sort: [SortDescriptor(\TimerTemplate.name, order: .forward)]) private var templates: [TimerTemplate]
    
    @State private var showingNewTemplate = false
    @State private var selectedTemplate: TimerTemplate?
    @State private var showingEditTemplate = false
    
    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Timer Templates",
                        systemImage: "timer",
                        description: Text("Create your first timer template to get started")
                    )
                } else {
                    ForEach(templates) { template in
                        TimerTemplateListRow(template: template) {
                            // Edit action guarded by isDataReady
                            guard isDataReady else { return }
                            prewarm(template)
                            selectedTemplate = template
                            showingEditTemplate = true
                        }
                    }
                    .onDelete(perform: deleteTemplates)
                }
            }
            .navigationTitle("Timer Templates")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New") {
                        guard isDataReady else { return }
                        showingNewTemplate = true
                    }
                    .disabled(!isDataReady)
                }
                
                if !templates.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                            .disabled(!isDataReady)
                    }
                }
            }
            .sheet(isPresented: $showingNewTemplate) {
                TimerTemplateEditor()
            }
            .sheet(isPresented: $showingEditTemplate) {
                if let template = selectedTemplate {
                    TimerTemplateEditor(existingTemplate: template)
                }
            }
        }
    }
    
    private func deleteTemplates(offsets: IndexSet) {
        guard isDataReady else { return }
        for index in offsets {
            context.delete(templates[index])
        }
        try? context.save()
    }
    
    
    // Touching relationships to ensure SwiftData realizes them before presenting the editor
    private func prewarm(_ template: TimerTemplate) {
        // Force access to commonly used properties to avoid first-render hiccups
        _ = template.name
        _ = template.templateDescription
        // Sort intervals to mirror what the editor does
        let _ = template.intervals.sorted { $0.order < $1.order }
        // Touch computed property
        _ = template.effectiveTotalTimeSeconds
    }
}


// MARK: - Timer Template List Row
struct TimerTemplateListRow: View {
    let template: TimerTemplate
    let onEdit: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(template.name)
                        .font(.headline)
                    
                    Spacer()
                    
                    if template.useCount > 0 {
                        Text("Used \(template.useCount) times")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let description = template.templateDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 36) {
                    //number of sets
                    if template.isRepeating {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                            Text("\(template.repeatCount ?? 1)x")
                        }
                    }
                    //number of reps within a set
                    if !template.intervals.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "repeat")
                            Text("\(template.intervals.first?.repetitions ?? 0)")
                        }
                    }
                    //rest time between intervals
                    if let restBetween = template.restTimeBetweenIntervals, restBetween > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "pause.circle")
                            Text(formatTime(restBetween))
                        }
                    }
                    // total time
                    if let totalTime = template.effectiveTotalTimeSeconds {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.badge.checkmark")
                            Text(formatTime(totalTime))
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if let lastUsed = template.lastUsedDate {
                    Text("Last used: \(lastUsed.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}
