//
//  SettingSheet.swift
//  Klettrack
//  Created by Shahar Noy on 12.10.25.
//

import SwiftUI

struct SettingsSheet: View {
    private enum SheetRoute: String, Identifiable {
        case about
        case contribute
        var id: String { rawValue }
    }

    @State private var sheetRoute: SheetRoute?

    @State private var hasRequestedReviewThisSession = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CatalogView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "square.grid.2x2")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Exercise Catalog")
                                    .font(.body)
                                Text("Your climbing and training exercises")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    
                    //metadata manager
                    NavigationLink {
                        ClimbMetaManagerView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Data Manager")
                                    .font(.body)
                                Text("Edit day types, styles, and gyms")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    //Media Manager
                    NavigationLink {
                        MediaManagerView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "photo.stack")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Gallery")
                                    .font(.body)
                                Text("Browse all climbs photos and videos")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    
                    NavigationLink {
                        TimerTemplatesListView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "timer")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Timer Templates")
                                    .font(.body)
                                Text("Create or customize timer templates")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    NavigationLink {
                        KlettrackWebSettingsView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "cloud")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("klettrack web")
                                    .font(.body)
                                Text("Manage cloud sync and account")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    NavigationLink {
                        BoardCredentialsSettingsView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "lock.circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Board Credentials")
                                    .font(.body)
                                Text("Manage TB2 and Kilter credentials")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }

                Section {
                    //rate the app
                    Button {
                        if !hasRequestedReviewThisSession {
                            if let url = URL(string: "itms-apps://apps.apple.com/app/id6754015176?action=write-review") {
                                UIApplication.shared.open(url)
                                hasRequestedReviewThisSession = true
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .imageScale(.medium)
                            Text("Rate klettrack")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    //Feature request / feedback button opens link to roadmap
                    Button {
                        if let url = URL(string: "https://klettrack.featurebase.app/") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "megaphone")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Got an idea? See what’s planned next")
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .buttonStyle(.plain)
                    // Contribute button opens AboutView.contribute
                    Button {
                        sheetRoute = .contribute
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: "lightbulb")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Why is klettrack free?")
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .buttonStyle(.plain)
                    
                    //About button opens AboutView.klettrack
                    Button {
                        sheetRoute = .about
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "info.circle")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("About")
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .buttonStyle(.plain)
                    
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        // About / Contribute sheet
        .sheet(item: $sheetRoute) { route in
            NavigationStack {
                Group {
                    switch route {
                    case .about:
                        AboutView.klettrack
                    case .contribute:
                        AboutView.contribute
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { sheetRoute = nil }
                    }
                }
            }
        }
    }
}
