//
//  UndoSupport.swift
//  Klettrack
//  Created by Shahar Noy on 13.10.25.
//

import SwiftUI
import SwiftData

private struct AttachUndoManager: ViewModifier {
    @Environment(\.undoManager) private var envUndo
    @Environment(\.modelContext) private var modelContext
    @State private var fallbackUndo = UndoManager()

    func body(content: Content) -> some View {
        content.onAppear {
            let before = modelContext.undoManager
            // Only set if not already set; prefer the scene’s undo manager, else fallback.
            if before == nil {
                if let env = envUndo {
                    modelContext.undoManager = env
                } else {
                    modelContext.undoManager = fallbackUndo
                }
            } else {
                // Debug: already set
                print("AttachUndoManager: modelContext.undoManager already set: \(debugPtr(before))")
                
            }
        }
    }

    private func debugPtr(_ any: AnyObject?) -> String {
        guard let any else { return "nil" }
        return String(describing: Unmanaged.passUnretained(any).toOpaque())
    }
}

extension View {
    func attachUndoManager() -> some View {
        modifier(AttachUndoManager())
    }
}
