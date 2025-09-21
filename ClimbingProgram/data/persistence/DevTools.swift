//
//  DevTools.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
// If you want a quick reset during development:

import SwiftData

#if DEBUG
struct DevTools {
    static func nukeAndReseed(_ ctx: ModelContext) {
        try? ctx.delete(model: SessionItem.self)
        try? ctx.delete(model: Session.self)
        //try? ctx.delete(model: PlanDay.self)
        //try? ctx.delete(model: Plan.self)
        try? ctx.delete(model: Exercise.self)
        try? ctx.delete(model: TrainingType.self)
        try? ctx.delete(model: Activity.self)
        try? ctx.save()
        SeedData.loadIfNeeded(ctx)
        applyCatalogUpdates(ctx)
    }
}
#endif
