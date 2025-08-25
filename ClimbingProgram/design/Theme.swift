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
        case .climbingSmall:  return .blue
        case .climbingReduced:return .brown
        case .core:           return .orange
        case .antagonist:     return .cyan
        case .rest:           return .purple
        case .vacation:       return .yellow
        case .sick:           return .red
        }
    }
}

// Map catalog categories to colors (align with DayType colors where it makes sense)
enum CatalogHue: String {
    case core, antagonist, climbing, other, bouldering

    var color: Color {
        switch self {
        case .core:        return .orange          // matches DayType.core
        case .antagonist:  return .cyan            // matches DayType.antagonist
        case .climbing:    return .green           // matches DayType.climbingFull
        case .other:       return .red
        case .bouldering:  return .pink
        }
    }
}

extension Activity {
    var hue: CatalogHue {
        let n = name.lowercased()
        if n.contains("core") { return .core }
        if n.contains("antagonist") || n.contains("stabil") { return .antagonist }
        if n.contains("climbing") { return .climbing }
        if n.contains("boulder") { return .bouldering }
        return .other
    }
}

// Pretty card style
struct CatalogCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let tint: Color
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(tint).frame(width: 12, height: 12)
                Text(title).font(.headline)
                Spacer()
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }
}

struct CatalogMiniCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let tint: Color
    @ViewBuilder var content: Content
    
    init(title: String, subtitle: String? = nil, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title).font(.subheadline).bold()
                Spacer()
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content.font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.25), lineWidth: 1))
    }




}
