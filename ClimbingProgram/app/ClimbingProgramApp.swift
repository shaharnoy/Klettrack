//
//  ClimbingProgramApp.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftUI
import SwiftData

@main
struct ClimbingProgramApp: App {
    private static let modelTypes: [any PersistentModel.Type] = [
        Activity.self, TrainingType.self, Exercise.self,
        SyncState.self, SyncMutation.self,
        Session.self, SessionItem.self,
        Plan.self, PlanDay.self,
        TimerTemplate.self, TimerInterval.self, TimerSession.self, TimerLap.self,
        ClimbEntry.self, ClimbStyle.self, ClimbGym.self, ClimbMedia.self
    ]

    nonisolated private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onAppear {
                    // Seeding happens when the view appears with proper context
                }
        }
        .backgroundTask(.appRefresh(SyncBackgroundRefresh.taskIdentifier)) {
            guard !Self.isRunningTests else { return }
            await authManager.handleBackgroundRefreshTask()
            SyncBackgroundRefreshScheduler.scheduleNextRefresh()
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            guard !Self.isRunningTests else { return }
            switch newPhase {
            case .active:
                SyncBackgroundRefreshScheduler.scheduleNextRefresh()
                Task { await authManager.handleAppDidBecomeActive() }
            case .background:
                SyncBackgroundRefreshScheduler.scheduleNextRefresh()
                authManager.handleAppDidEnterBackground()
            case .inactive:
                authManager.handleAppDidEnterBackground()
                break
            @unknown default:
                break
            }
        }
        .modelContainer(for: Self.modelTypes, inMemory: Self.isRunningTests)
    }
}
