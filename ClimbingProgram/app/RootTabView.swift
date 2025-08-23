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
    @State private var isDataReady = false
    
    var body: some View {
        TabView {
            CatalogView()
                .tabItem { Label("Catalog", systemImage: "square.grid.2x2") }
                .environment(\.isDataReady, isDataReady)
            
            PlansListView()
                .tabItem { Label("Plans", systemImage: "calendar") }
                .environment(\.isDataReady, isDataReady)
            
            LogView()
                .tabItem { Label("Log", systemImage: "square.and.pencil") }
                .environment(\.isDataReady, isDataReady)
            
            ProgressViewScreen()
                .tabItem { Label("Progress", systemImage: "chart.bar") }
                .environment(\.isDataReady, isDataReady)
        }
        .task {
            await initializeData()
        }
    }
    
    @MainActor
    private func initializeData() async {
        // Small delay to ensure SwiftData container is fully ready
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        SeedData.loadIfNeeded(context)
        
        // Non-destructive catalog deltas migration (run once per key)
        runOnce(per: "catalog_2025-08-21_bouldering") {
            applyCatalogUpdates(context)
        }
        
        // Ensure all changes are committed
        try? context.save()
        
        // Small additional delay to ensure everything is settled
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        isDataReady = true
    }
}

// MARK: - Environment Key for Data Ready State

private struct DataReadyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isDataReady: Bool {
        get { self[DataReadyKey.self] }
        set { self[DataReadyKey.self] = newValue }
    }
}
