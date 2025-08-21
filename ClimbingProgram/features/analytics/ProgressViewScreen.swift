//
//  ProgressViewScreen.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData
import Charts   // Apple framework

struct ProgressViewScreen: View {
    @Query(sort: \Session.date) private var sessions: [Session]

    var totalExercises: Int { sessions.flatMap { $0.items }.count }

    var body: some View {
        NavigationStack {
            List {
                Section("Totals") {
                    HStack { Text("Sessions"); Spacer(); Text("\(sessions.count)") }
                    HStack { Text("Total exercises"); Spacer(); Text("\(totalExercises)") }
                }

                Section("Activity breakdown (by keyword)") {
                    // Simple heuristic: group by first word of exercise name
                    let groups = Dictionary(grouping: sessions.flatMap { $0.items }) { item in
                        item.exerciseName.components(separatedBy: " ").first ?? "Other"
                    }
                    let rows = groups.map { (key: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count }

                    if rows.isEmpty {
                        Text("No data yet. Log a session!").foregroundStyle(.secondary)
                    } else {
                        Chart(rows, id: \.key) { row in
                            BarMark(x: .value("Count", row.count), y: .value("Activity", row.key))
                        }
                        .frame(minHeight: 220)
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }
}

