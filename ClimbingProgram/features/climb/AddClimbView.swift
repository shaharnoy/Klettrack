//
//  AddClimbView.swift
//  Klettrack
//  Created by Shahar Noy on 28.08.25.
//

import SwiftUI
import SwiftData

struct AddClimbView: View {
    let bulkCount: Int
    let onSave: ((ClimbEntry) -> Void)?

    init(bulkCount: Int = 1, onSave: ((ClimbEntry) -> Void)? = nil) {
        self.bulkCount = max(1, bulkCount)
        self.onSave = onSave
    }

    var body: some View {
        ClimbLogForm(
            title: "Add Climb",
            initialDate: Date(),
            existingClimb: nil,
            bulkCount: bulkCount,
            onSave: onSave
        )
    }
}
