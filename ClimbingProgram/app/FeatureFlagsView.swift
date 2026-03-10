//
//  FeatureFlagsView.swift
//  Klettrack
//  Created by Shahar Noy on 08.02.26.
//

import SwiftUI

struct FeatureFlagsView: View {
    @AppStorage(FeatureFlags.forcePreferMyGradeInProgress) private var forcePreferMyGradeInProgress = false
    @AppStorage(FeatureFlags.showNotesWhenGymMissing) private var showNotesWhenGymMissing = false
    @AppStorage(FeatureFlags.persistProgressFilters) private var persistProgressFilters = false
    @AppStorage(FeatureFlags.klettrackWebSettings) private var klettrackWebSettings = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $klettrackWebSettings) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Klettrack Web")
                        Text("Shows the Klettrack Web settings entry on the main settings page.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

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

                Toggle(isOn: $persistProgressFilters) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remember Progress Filters")
                        Text("Saves and restores the last used filters on the Progress screen.")
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
