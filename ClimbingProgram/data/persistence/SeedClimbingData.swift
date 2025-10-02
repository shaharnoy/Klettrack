//
//  SeedClimbingData.swift
//  Klettrack
//  Created by Shahar Noy on 28.08.25.
//

import SwiftData

struct SeedClimbingData {
    static func loadIfNeeded(_ context: ModelContext) {
        let styleCount = (try? context.fetchCount(FetchDescriptor<ClimbStyle>())) ?? 0
        let gymCount = (try? context.fetchCount(FetchDescriptor<ClimbGym>())) ?? 0
        
        // Only seed if empty
        guard styleCount == 0 && gymCount == 0 else { return }
        
        // Seed default climbing styles
        for styleName in ClimbingDefaults.defaultStyles {
            let style = ClimbStyle(name: styleName, isDefault: true)
            context.insert(style)
        }
        
        // Seed default gyms
        for gymName in ClimbingDefaults.defaultGyms {
            let gym = ClimbGym(name: gymName, isDefault: true)
            context.insert(gym)
        }
        
        try? context.save()
    }
    
    static func nukeAndReseed(_ context: ModelContext) {
        // Delete all climbing data
        try? context.delete(model: ClimbEntry.self)
        try? context.delete(model: ClimbStyle.self)
        try? context.delete(model: ClimbGym.self)
        try? context.save()
        
        // Seed fresh
        loadIfNeeded(context)
    }
}
