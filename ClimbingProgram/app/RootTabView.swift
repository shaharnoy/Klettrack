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
            CatalogView()
                .tabItem { Label("Catalog", systemImage: "square.grid.2x2") }
            
            PlansListView()
                .tabItem { Label("Plans", systemImage: "calendar") }
            
            LogView()
                .tabItem { Label("Log", systemImage: "square.and.pencil") }
            
            ProgressViewScreen()
                .tabItem { Label("Progress", systemImage: "chart.bar") }
        }
        .task {
            SeedData.loadIfNeeded(context)
            //SeedData.nukeAndReseed(context)  // <- uncomment, run once, then comment it out
            // Non-destructive catalog deltas migration (run once per key)
            runOnce(per: "catalog_2025-08-21_bouldering") {
                applyCatalogUpdates(context)
            }
        }
    }
    
}
