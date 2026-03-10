//
//  AddClimbView.swift
//  Klettrack
//  Created by Shahar Noy on 28.08.25.
//

import SwiftUI
import SwiftData

struct AddClimbView: View {
    let prefillClimb: ClimbEntry?
    let initialDate: Date
    let bulkCount: Int
    let onSave: ((ClimbEntry) -> Void)?

    init(
        prefillClimb: ClimbEntry? = nil,
        initialDate: Date = Date(),
        bulkCount: Int = 1,
        onSave: ((ClimbEntry) -> Void)? = nil
    ) {
        self.prefillClimb = prefillClimb
        self.initialDate = initialDate
        self.bulkCount = max(1, bulkCount)
        self.onSave = onSave
    }

    var body: some View {
        ClimbLogForm(
            title: prefillClimb == nil ? "Add Climb" : "Clone Climb",
            initialDate: initialDate,
            existingClimb: nil,
            prefillClimb: prefillClimb,
            bulkCount: bulkCount,
            onSave: onSave
        )
    }
}
