//
//  InfoLabel.swift
//  ClimbingProgram
//
//  Created by Shahar Noy on 17.11.25.
//

import SwiftUI

// A single-line label with a floating "info" button in the top-right corner
struct InfoLabel: View {
    let text: String
    let helpMessage: String
    let font: Font
    let labelWidth: CGFloat?

    @State private var showHelp = false

    init(
        text: String,
        helpMessage: String,
        font: Font = .subheadline,
        labelWidth: CGFloat? = nil
    ) {
        self.text = text //button text
        self.helpMessage = helpMessage // the actual text
        self.font = font
        self.labelWidth = labelWidth
    }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .frame(width: labelWidth, alignment: .leading)
            .padding(.trailing, labelWidth == nil ? 16 : 0) //dynamic padding for the i button based on the length of the button text
            .overlay(alignment: .topTrailing) {
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(
                    isPresented: $showHelp,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(helpMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(minWidth: 300, maxWidth: 340, maxHeight: 400, alignment: .init(horizontal: .center, vertical: .top))
                    .presentationCompactAdaptation(.popover)
                }
            }
    }
}
