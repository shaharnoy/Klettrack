//
//  RootTabView.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            TrainingCatalogView()
                .tabItem { Label("Training", systemImage: "dumbbell") }

            LogView()
                .tabItem { Label("Log", systemImage: "square.and.pencil") }

            ProgressViewScreen()
                .tabItem { Label("Progress", systemImage: "chart.bar") }
        }
        .task {
            SeedData.loadIfNeeded(context)
        }
    }
}
