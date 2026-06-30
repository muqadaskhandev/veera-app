import BackgroundTasks
import Foundation
import HealthKit

extension Notification.Name {
    static let healthKitDataUpdated = Notification.Name("verra.healthkit.updated")
}

/// Observes HealthKit changes and enables background delivery for connected clients.
enum HealthKitBackgroundService {
    private static let store = HKHealthStore()
    private static var observerQuery: HKObserverQuery?

    static func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard observerQuery == nil else { return }

        let types: [HKSampleType] = [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
        ]

        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }

        guard let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let query = HKObserverQuery(sampleType: steps, predicate: nil) { _, _, error in
            guard error == nil else { return }
            NotificationCenter.default.post(name: .healthKitDataUpdated, object: nil)
        }
        observerQuery = query
        store.execute(query)
    }
}

enum HealthBackgroundSync {
    static let taskIdentifier = "com.verra.health.sync"
    private static let lastBackgroundSyncKey = "verra.health.lastBackgroundSync"

    /// Register the BGAppRefresh task handler. Call once at app launch.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Request the next background refresh after a successful foreground sync.
    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Foreground launch sync when data is stale (default: older than 1 hour).
    @MainActor
    static func syncOnLaunchIfNeeded(
        wearables: WearableConnectionStore,
        healthData: HealthDataStore,
        staleAfter seconds: TimeInterval = 3600
    ) async {
        guard wearables.hasAnyConnection else { return }
        if let last = wearables.lastSynced,
           Date().timeIntervalSince(last) < seconds {
            return
        }
        await wearables.syncNow(healthData: healthData)
        UserDefaults.standard.set(Date(), forKey: lastBackgroundSyncKey)
        scheduleNextRefresh()
    }

    /// Entry point for BGAppRefreshTask and SwiftUI `.backgroundTask`.
    @MainActor
    static func performBackgroundSync() async -> Bool {
        guard AuthStore.accessToken != nil else { return false }

        let wearables = WearableConnectionStore()
        await wearables.refreshFromServer()
        guard wearables.hasAnyConnection else { return false }

        let healthData = HealthDataStore()
        await wearables.syncNow(healthData: healthData)
        UserDefaults.standard.set(Date(), forKey: lastBackgroundSyncKey)
        scheduleNextRefresh()
        return wearables.lastSyncError == nil
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task { @MainActor in
            let success = await performBackgroundSync()
            task.setTaskCompleted(success: success)
        }
    }
}
