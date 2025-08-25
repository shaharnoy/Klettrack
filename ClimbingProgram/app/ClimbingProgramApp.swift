//
//  ClimbingProgramApp.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData

@main
struct ClimbingProgramApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onAppear {
                    // no-op; seeding happens in .task below
                }
                .task {
                    // Seed after model container exists
                }
        }
        .modelContainer(for: [
            Activity.self, TrainingType.self, Exercise.self,
            Session.self, SessionItem.self,
            Plan.self, PlanDay.self,
            TimerTemplate.self, TimerInterval.self, TimerSession.self, TimerLap.self
        ])

    }
}
