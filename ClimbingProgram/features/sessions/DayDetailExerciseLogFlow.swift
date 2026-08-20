import Foundation
import SwiftData

struct DayDetailExerciseLogPreparation {
    let persistedSession: Session
    let sessionForSheet: Session
}

@MainActor
enum DayDetailExerciseLogFlow {
    static func prepare(
        existingSession: Session?,
        date: Date,
        in context: ModelContext
    ) throws -> DayDetailExerciseLogPreparation {
        let persistedSession: Session

        if let existingSession {
            persistedSession = existingSession
        } else {
            let newSession = Session(date: date)
            context.insert(newSession)
            try context.save()
            persistedSession = newSession
        }

        return DayDetailExerciseLogPreparation(
            persistedSession: persistedSession,
            sessionForSheet: persistedSession
        )
    }
}
