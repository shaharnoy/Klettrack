//
//  Theme.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI

extension DayType {
    var color: Color {
        switch self {
        case .climbingFull:   return .green
        case .climbingSmall:  return .teal
        case .climbingReduced:return .mint
        case .core:           return .orange
        case .antagonist:     return .cyan
        case .rest:           return .purple
        case .vacation:       return .yellow
        case .sick:           return .red
        }
    }
}
