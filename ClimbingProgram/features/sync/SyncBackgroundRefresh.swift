//
//  SyncBackgroundRefresh.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import BackgroundTasks
import Foundation

enum SyncBackgroundRefresh {
    static let taskIdentifier = "com.somenoys.klettrack.sync.refresh"
    static let earliestBeginInterval: TimeInterval = 15 * 60
}

enum SyncBackgroundRefreshScheduler {
    static func scheduleNextRefresh(after interval: TimeInterval = SyncBackgroundRefresh.earliestBeginInterval) {
        let request = BGAppRefreshTaskRequest(identifier: SyncBackgroundRefresh.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: max(60, interval))

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("Unable to schedule background refresh: \(error.localizedDescription)")
            #endif
        }
    }
}
