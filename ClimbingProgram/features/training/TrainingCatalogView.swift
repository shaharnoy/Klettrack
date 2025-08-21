//
//  TrainingCatalogView.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData

struct TrainingCatalogView: View {
    @Query(sort: \Activity.name) private var activities: [Activity]

    var body: some View {
        NavigationStack {
            List {
                ForEach(activities) { activity in
                    NavigationLink(activity.name) {
                        TrainingTypesView(activity: activity)
                    }
                }
            }
            .navigationTitle("Training")
        }
    }
}

struct TrainingTypesView: View {
    let activity: Activity
    var body: some View {
        List {
            ForEach(activity.types) { t in
                NavigationLink(destination: ExercisesView(trainingType: t)) {
                    VStack(alignment: .leading) {
                        Text(t.name).bold()
                        if let area = t.area { Text(area).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle(activity.name)
    }
}

struct ExercisesView: View {
    let trainingType: TrainingType
    var body: some View {
        List {
            // Header row
            HStack {
                Text("Exercise").bold()
                Spacer()
                Text("REPS").bold().frame(minWidth: 80, alignment: .trailing)
                Text("SETS/REST").bold().frame(minWidth: 100, alignment: .trailing)
            }
            .foregroundStyle(.secondary)

            ForEach(trainingType.exercises) { ex in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ex.name)
                        Spacer()
                        Text(ex.repsText ?? "—").frame(minWidth: 80, alignment: .trailing)
                        Text(ex.setsText ?? ex.restText ?? "—").frame(minWidth: 100, alignment: .trailing)
                    }
                    if let rest = ex.restText, (ex.setsText?.isEmpty ?? true) {
                        Text(rest).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let notes = ex.notes {
                        Text(notes).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(trainingType.name)
    }
}
