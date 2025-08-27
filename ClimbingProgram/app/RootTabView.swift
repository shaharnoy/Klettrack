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
        selectedTab = 5 // Timer tab index (updated from 4 to 5)
    }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @State private var isDataReady = false
    @StateObject private var timerAppState = TimerAppState()
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            Group {
                switch timerAppState.selectedTab {
                case 0:
                    CatalogView()
                        .environment(\.isDataReady, isDataReady)
                        .environmentObject(timerAppState)
                case 1:
                    PlansListView()
                        .environment(\.isDataReady, isDataReady)
                        .environmentObject(timerAppState)
                case 2:
                    ClimbView()
                        .environment(\.isDataReady, isDataReady)
                        .environmentObject(timerAppState)
                case 3:
                    LogView()
                        .environment(\.isDataReady, isDataReady)
                        .environmentObject(timerAppState)
                case 4:
                    ProgressViewScreen()
                        .environment(\.isDataReady, isDataReady)
                        .environmentObject(timerAppState)
                case 5:
                    TimerView(planDay: timerAppState.currentPlanDay)
                        .environment(\.isDataReady, isDataReady)
                        .environmentObject(timerAppState)
                default:
                    CatalogView()
                        .environment(\.isDataReady, isDataReady)
                        .environmentObject(timerAppState)
                }
            }
            
            // Custom tab bar
            CustomTabBar(selectedTab: $timerAppState.selectedTab)
        }
        .task {
            await initializeData()
            //SeedData.nukeAndReseed(context) // Uncomment this line to reset data during development
            //SeedTimerTemplates.nukeAndReseed(context) // Uncomment this line to reset data during development
        }
    }
    
    @MainActor
    private func initializeData() async {
        // Longer delay to ensure SwiftData container is fully ready
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        SeedData.loadIfNeeded(context)
        
        // Seed timer templates
        SeedTimerTemplates.loadIfNeeded(context)
        
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
