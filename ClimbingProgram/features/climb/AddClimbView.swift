//
//  AddClimbView.swift
//  Klettrack
//  Created by Shahar Noy on 28.08.25.
//

import SwiftUI
import SwiftData

struct AddClimbView: View {
    let onSave: ((ClimbEntry) -> Void)?

    init(onSave: ((ClimbEntry) -> Void)? = nil) {
        self.onSave = onSave
    }

    var body: some View {
        ClimbLogForm(
            title: "Add Climb",
            initialDate: Date(),
            existingClimb: nil,
            onSave: onSave
        )
    }
}
