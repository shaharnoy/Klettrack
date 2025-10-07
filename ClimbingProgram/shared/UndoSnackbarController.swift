//
//  UndoSnackbarController.swift
//  ClimbingProgram
//
//  Created by Shahar Noy on 07.10.25.
//

import Foundation
import SwiftUI

@MainActor
public final class UndoSnackbarController: ObservableObject {
    @Published public private(set) var isVisible: Bool = false
    @Published public private(set) var message: String = ""
    public private(set) var duration: TimeInterval = 10

    private var onUndoAction: (() -> Void)?
    private var task: Task<Void, Never>?

    public init() {}

    public func show(message: String, duration: TimeInterval? = nil, onUndo: @escaping () -> Void) {
        dismiss()
        self.message = message
        self.duration = duration ?? 10
        self.onUndoAction = onUndo
        self.isVisible = true

        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.duration * 1_000_000_000))
            await MainActor.run {
                if self.isVisible { self.dismiss() }
            }
        }
    }

    public func performUndo() {
        let action = onUndoAction
        dismiss()
        action?()
    }

    public func dismiss() {
        task?.cancel()
        task = nil
        isVisible = false
        message = ""
        onUndoAction = nil
    }
}
