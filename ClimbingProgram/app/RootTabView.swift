//
//  RootTabView.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData

// Shared timer state to ensure only one timer instance
class TimerAppState: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var currentPlanDay: PlanDay? = nil
    
    func switchToTimer(with planDay: PlanDay? = nil) {
        currentPlanDay = planDay
        selectedTab = 4 // Timer tab index
    }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @State private var isDataReady = false
    @StateObject private var timerAppState = TimerAppState()
    
    var body: some View {
        TabView(selection: $timerAppState.selectedTab) {
            CatalogView()
                .tabItem { Label("Catalog", systemImage: "square.grid.2x2") }
                .environment(\.isDataReady, isDataReady)
                .environmentObject(timerAppState)
                .tag(0)
            
            PlansListView()
                .tabItem { Label("Plans", systemImage: "calendar") }
                .environment(\.isDataReady, isDataReady)
                .environmentObject(timerAppState)
                .tag(1)
            
            LogView()
                .tabItem { Label("Log", systemImage: "square.and.pencil") }
                .environment(\.isDataReady, isDataReady)
                .environmentObject(timerAppState)
                .tag(2)
            
            ProgressViewScreen()
                .tabItem { Label("Progress", systemImage: "chart.bar") }
                .environment(\.isDataReady, isDataReady)
                .environmentObject(timerAppState)
                .tag(3)
            
            TimerView(planDay: timerAppState.currentPlanDay)
                .tabItem { Label("Timer", systemImage: "timer") }
                .environment(\.isDataReady, isDataReady)
                .environmentObject(timerAppState)
                .tag(4)
        }
        .task {
            await initializeData()
            //SeedData.nukeAndReseed(context) // Uncomment this line to reset data during development
        }
    }
    
    @MainActor
    private func initializeData() async {
        // Longer delay to ensure SwiftData container is fully ready
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        SeedData.loadIfNeeded(context)
        
        // Non-destructive catalog deltas migration (run once per key)
        runOnce(per: "catalog_2025-08-21_bouldering") {
            applyCatalogUpdates(context)
        }
        
        // Ensure all changes are committed
        try? context.save()
        
        // Additional delay to ensure everything is settled
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
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
