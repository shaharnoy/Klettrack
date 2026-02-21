//
//  SyncDebouncer.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation

actor SyncDebouncer {
    private var pendingTask: Task<Void, Never>?

    func schedule(after delay: Duration, operation: @escaping @Sendable () async -> Void) {
        pendingTask?.cancel()
        pendingTask = Task {
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
                await operation()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }
}
