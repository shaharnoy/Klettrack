//
//  CustomTabBar.swift
//  Klettrack
//  Created by Shahar Noy on 27.08.25.
//

import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    
    private let tabs: [(title: String, icon: String, tag: Int)] = [
        ("Catalog", "square.grid.2x2", 0),
        ("Plans", "calendar", 1),
        ("Climb", "figure.climbing", 2),
        ("Log", "book.pages", 3),
        ("Progress", "chart.xyaxis.line", 4),
        ("Timer", "stopwatch", 5)
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.tag) { tab in
                Button(action: {
                    selectedTab = tab.tag
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(selectedTab == tab.tag ? .blue : .secondary)
                        
                        Text(tab.title)
                            .font(.caption2)
                            .foregroundColor(selectedTab == tab.tag ? .blue : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

#Preview {
    CustomTabBar(selectedTab: .constant(0))
}
