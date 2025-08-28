//
//  RootTabView.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData
import Combine

// Shared timer state to ensure only one timer instance
@MainActor
class TimerAppState: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var currentPlanDay: PlanDay? = nil
    
    // Navigation path storage for each tab to preserve navigation state
    @Published var catalogNavigationPath = NavigationPath()
    @Published var plansNavigationPath = NavigationPath()
    @Published var climbNavigationPath = NavigationPath()
    @Published var logNavigationPath = NavigationPath()
    @Published var progressNavigationPath = NavigationPath()
    
    // Reference to shared timer manager
    private let sharedTimerManager = SharedTimerManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupTimerObservation()
    }
    
    deinit {
        // Explicit cleanup
        cancellables.removeAll()
    }
    
    private func setupTimerObservation() {
        // Monitor timer state and auto-switch to timer tab when timer becomes active
        sharedTimerManager.$isTimerActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self = self else { return }
                if isActive && self.selectedTab != 5 {
                    // Timer is running/paused and we're not on timer tab - switch to it
                    self.selectedTab = 5
                }
            }
            .store(in: &cancellables)
    }
    
    func switchToTimer(with planDay: PlanDay? = nil) {
        currentPlanDay = planDay
        selectedTab = 5 // Timer tab index
    }
    
    var isTimerActive: Bool {
        sharedTimerManager.isTimerActive
    }
}

// MARK: - Navigation Types for Plans
// Hashable wrapper types for navigation
struct PlanNavigationItem: Hashable {
    let planId: UUID
    
    init(planId: UUID) {
        self.planId = planId
    }
    
    init(plan: Plan) {
        self.planId = plan.id
    }
}

struct PlanDayNavigationItem: Hashable {
    let planDayId: UUID
    
    init(planDayId: UUID) {
        self.planDayId = planDayId
    }
    
    init(planDay: PlanDay) {
        self.planDayId = planDay.id
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
                    NavigationStack(path: $timerAppState.catalogNavigationPath) {
                        CatalogView()
                            .environment(\.isDataReady, isDataReady)
                            .environmentObject(timerAppState)
                    }
                case 1:
                    NavigationStack(path: $timerAppState.plansNavigationPath) {
                        PlansListView()
                            .environment(\.isDataReady, isDataReady)
                            .environmentObject(timerAppState)
                    }
                case 2:
                    NavigationStack(path: $timerAppState.climbNavigationPath) {
                        ClimbView()
                            .environment(\.isDataReady, isDataReady)
                            .environmentObject(timerAppState)
                    }
                case 3:
                    NavigationStack(path: $timerAppState.logNavigationPath) {
                        LogView()
                            .environment(\.isDataReady, isDataReady)
                            .environmentObject(timerAppState)
                    }
                case 4:
                    NavigationStack(path: $timerAppState.progressNavigationPath) {
                        ProgressViewScreen()
                            .environment(\.isDataReady, isDataReady)
                            .environmentObject(timerAppState)
                    }
                case 5:
                    TimerView(planDay: timerAppState.currentPlanDay)
                        .environment(\.isDataReady, isDataReady)
                        .environmentObject(timerAppState)
                default:
                    NavigationStack(path: $timerAppState.catalogNavigationPath) {
                        CatalogView()
                            .environment(\.isDataReady, isDataReady)
                            .environmentObject(timerAppState)
                    }
                }
            }
            
            // Custom tab bar
            CustomTabBar(selectedTab: $timerAppState.selectedTab)
        }
        .task {
            await initializeData()
            //SeedData.nukeAndReseed(context) // Uncomment this line to reset data during development
            //SeedTimerTemplates.nukeAndReseed(context) // Uncomment this line to reset data during development
            //SeedClimbingData.nukeAndReseed(context) // Uncomment this line to reset data during development
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
