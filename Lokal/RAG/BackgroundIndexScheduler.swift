//
//  BackgroundIndexScheduler.swift
//  Lokal
//
//  Registers a `BGProcessingTask` so the system can grant the app a few
//  minutes of background execution for incremental RAG indexing. The
//  task is scheduled each time the app enters the background and runs
//  at most once per hour.
//

import BackgroundTasks
import Foundation

enum BackgroundIndexScheduler {

    static let taskID = "com.slavkoklincov.lokal.ragindex"

    /// Register the handler once, at app startup.
    @MainActor
    static func register(indexingService: IndexingService) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskID,
            using: .main
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                indexingService.checkStaleSources()
                // The indexing runs asynchronously; mark success immediately.
                // If the system reclaims the app, IndexingService.cancel()
                // is called via the expiration handler below.
                processingTask.setTaskCompleted(success: true)
            }
            processingTask.expirationHandler = {
                Task { @MainActor in
                    indexingService.cancel()
                }
            }
            // Schedule the next run after this one completes.
            scheduleNext()
        }
    }

    /// Submit a request for the next background processing slot.
    static func scheduleNext() {
        let request = BGProcessingTaskRequest(identifier: taskID)
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        try? BGTaskScheduler.shared.submit(request)
    }
}
