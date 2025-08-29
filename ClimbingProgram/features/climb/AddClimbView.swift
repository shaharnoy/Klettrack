//
//  AddClimbView.swift
//  ClimbingProgram
//
//  Created by AI Assistant on 28.08.25.
//

import SwiftUI
import SwiftData

struct AddClimbView: View {
    var body: some View {
        ClimbLogForm(title: "Add Climb")
    }
}

#Preview {
    AddClimbView()
        .modelContainer(for: [ClimbEntry.self, ClimbStyle.self, ClimbGym.self])
}
