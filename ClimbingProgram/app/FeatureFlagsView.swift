//
//  FeatureFlagsView.swift
//  Klettrack
//  Created by Shahar Noy on 08.02.26.
//

import SwiftUI

struct FeatureFlagsView: View {
    @AppStorage(FeatureFlags.forcePreferMyGradeInProgress) private var forcePreferMyGradeInProgress = false
    @AppStorage(FeatureFlags.showNotesWhenGymMissing) private var showNotesWhenGymMissing = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $forcePreferMyGradeInProgress) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Prefer My Grade (Progress)")
                        Text("Turns on Prefer My Grade by default in Progress filters.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Toggle(isOn: $showNotesWhenGymMissing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Notes When Gym Missing")
                        Text("In climb rows, show notes if gym is not selected.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("Feature Flags")
        .navigationBarTitleDisplayMode(.inline)
    }
}

