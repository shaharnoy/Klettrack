//
//  undobanner.swift
//  ClimbingProgram
//
//  Created by Shahar Noy on 07.10.25.
//

import SwiftUI

public struct UndoBanner: View {
    public let message: String
    public let onUndo: () -> Void
    public let onDismiss: () -> Void
    public var duration: TimeInterval

    @State private var progress: CGFloat = 1.0

    public init(message: String,
                duration: TimeInterval = 10,
                onUndo: @escaping () -> Void,
                onDismiss: @escaping () -> Void) {
        self.message = message
        self.duration = duration
        self.onUndo = onUndo
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button("Undo") { onUndo() }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                let barHeight: CGFloat = 3
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: max(0, proxy.size.width * progress))
                        .animation(.linear(duration: duration), value: progress)
                }
                .frame(height: barHeight)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .allowsHitTesting(false)
            }
        }
        .shadow(radius: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). Undo")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            progress = 1.0
            progress = 0.0
        }
    }
}
