//
//  BulkClimbCountPrompt.swift
//  ClimbingProgram
//
//  Created by Shahar Noy on 17.01.26.
//

import SwiftUI

extension View {
    func bulkClimbCountPrompt(
        isPresented: Binding<Bool>,
        countText: Binding<String>,
        title: String = "Bulk Log climbs",
        message: String = "How many?",
        confirmTitle: String = "Continue",
        onConfirm: @escaping (Int) -> Void
    ) -> some View {
        alert(title, isPresented: isPresented) {
            TextField("How many?", text: countText)
                .keyboardType(.numberPad)

            Button(confirmTitle) {
                let raw = Int(countText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
                onConfirm(max(1, raw))
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
