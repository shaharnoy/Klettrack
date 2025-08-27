//
//  ClimbView.swift
//  ClimbingProgram
//
//  Created by AI Assistant on 27.08.25.
//

import SwiftUI

struct ClimbView: View {
    @Environment(\.isDataReady) private var isDataReady
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Climb")
                    .font(.largeTitle.bold())
                
                Text("Your climbing session tracker")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Climb")
            .navigationBarTitleDisplayMode(.large)
        }
        .opacity(isDataReady ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isDataReady)
    }
}

#Preview {
    ClimbView()
        .environment(\.isDataReady, true)
}
