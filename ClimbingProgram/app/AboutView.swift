//
//  AboutView.swift
//  Klettrack
//  Created by Shahar Noy on 13.10.25.
//

import SwiftUI
import UniformTypeIdentifiers

struct SimpleMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseBlocks(from: markdown), id: \.id) { block in
                switch block.kind {
                case .h1(let text):
                    Text(text)
                        .font(.title.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .h2(let text):
                    Text(text)
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                case .paragraph(let text):
                    LinkifiedText(text: text)
                case .ul(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•")
                                LinkifiedText(text: item)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: Parser
    private func parseBlocks(from md: String) -> [MDBlock] {
        let normalized = md.replacingOccurrences(of: "\r\n", with: "\n")
        let chunks = normalized.components(separatedBy: "\n\n")
        var blocks: [MDBlock] = []

        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("# ") {
                blocks.append(.init(kind: .h1(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))))
                continue
            }
            if trimmed.hasPrefix("## ") {
                blocks.append(.init(kind: .h2(String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces))))
                continue
            }

            // unordered list? (lines starting with "- " or "• ")
            let lines = trimmed.components(separatedBy: .newlines)
            if lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("• ") }) {
                let items = lines.map { line -> String in
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") { return String(t.dropFirst(2)) }
                    if t.hasPrefix("• ") { return String(t.dropFirst(2)) }
                    return t
                }
                blocks.append(.init(kind: .ul(items)))
                continue
            }

            // fallback = paragraph
            blocks.append(.init(kind: .paragraph(trimmed)))
        }
        return blocks
    }

    private struct MDBlock: Identifiable {
        enum Kind: Equatable {
            case h1(String), h2(String), paragraph(String), ul([String])
        }
        let id = UUID()
        let kind: Kind
    }
}

// Renders a string with auto-linked URLs using AttributedString, within SwiftUI Text
private struct LinkifiedText: View {
    let text: String
    var body: some View {
        if let rich = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                           failurePolicy: .returnPartiallyParsedIfPossible)
        ) {
            Text(rich)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
        } else {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
        }
    }
}

// MARK: - Your AboutView (unchanged header/links, new body renderer)
struct AboutView: View {
    let aboutText: String
    let websiteURL: URL?
    let issuesURL: URL?
    let privacyURL: URL?

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "App"
    }

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appName).font(.title3.weight(.semibold))
                        Text(versionString).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.setValue(versionString, forPasteboardType: UTType.plainText.identifier)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy version")
                }

                // About (SwiftUI-only Markdown)
                SimpleMarkdownView(markdown: aboutText)

                // Links
                if websiteURL != nil || issuesURL != nil || privacyURL != nil {
                    Divider().padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        if let u = websiteURL { Link("Website / Support", destination: u) }
                        if let u = issuesURL  { Link("Report an Issue",   destination: u) }
                        if let u = privacyURL { Link("Privacy Policy",    destination: u) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Factory
extension AboutView {
    static var klettrack: AboutView {
        AboutView(
            aboutText:
            """
            # Klettrack

            Plan, log, and analyze your climbing and training.

            ## What Klettrack does
            
            - Log climbs by style, grade, angle, holds, and colors
            - Plan and run training sessions with an interval timer
            - Import and export (e.g., CSV) to move your data where you want
            - Optional viewing/sync of sends from compatible board platforms

            ## Privacy
            
            Your data stays on your device by default. No ads. No tracking.
            Read our full policy: https://github.com/shaharnoy/Klettrack/wiki/Privacy-Policy

            ## Open Source & Licenses
            
            Klettrack © 2025 [Shahar Noy]. All rights reserved.
            This binary build is distributed under a proprietary license.
            The source code is available under the GNU GPL v3:
            https://github.com/shaharnoy/Klettrack

            ## Trademarks & Attribution
            
            “Kilter Board,” “Tension Board,” , "Aurora Climbing" and other brand names are trademarks of their respective owners.
            Klettrack is an independent open source project and is not affiliated with, endorsed by, or sponsored by those brands.
            """,
            websiteURL: URL(string: "https://github.com/shaharnoy/Klettrack"),
            issuesURL: URL(string:  "https://klettrack.featurebase.app/"),
            privacyURL: URL(string: "https://github.com/shaharnoy/Klettrack/wiki/Privacy-Policy")
        )
    }

    static var contribute: AboutView {
        AboutView(
            aboutText:
            """
            # Why is Klettrack free?

            Klettrack is built by climbers, for climbers as a community project.
            
            Klettrack is **open-source** and completely **free of ads or tracking**.
            
            We’ve learned so much from the community over the years, so this app is our way of giving something back.  

            ## If you want to support the project, you can:

            - Share feedback or ideas  
            - Help improve the code
            - Spread the word to other climbers  

            """,
            websiteURL: URL(string: "https://github.com/shaharnoy/Klettrack"),
            issuesURL: URL(string: "https://klettrack.featurebase.app/"),
            privacyURL: URL(string: "https://github.com/shaharnoy/Klettrack/wiki/Privacy-Policy")
        )
    }
}
