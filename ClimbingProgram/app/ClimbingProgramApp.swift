//
//  ClimbingProgramApp.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftUI
import SwiftData

@main
struct ClimbingProgramApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onAppear {
                    // Seeding happens when the view appears with proper context
                }
        }
        .modelContainer(for: [
            Activity.self, TrainingType.self, BoulderCombination.self, Exercise.self,
            Session.self, SessionItem.self,
            DayLog.self, DayTag.self,
            Plan.self, PlanDay.self, PlanKindModel.self, DayTypeModel.self,
            PlanExerciseDefinition.self,
            TimerTemplate.self, TimerInterval.self, TimerSession.self, TimerLap.self,
            ClimbEntry.self, ClimbStyle.self, ClimbGym.self, ClimbMedia.self,
            TB2ClimbMetadata.self, TB2ClimbStatsMetadata.self
        ])
    }
}
