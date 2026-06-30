//
//  VerraOSApp.swift
//  VerraOS
//

import BackgroundTasks
import SwiftUI

@main
struct VerraOSApp: App {
    init() {
        HealthBackgroundSync.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .backgroundTask(.appRefresh(HealthBackgroundSync.taskIdentifier)) {
            _ = await HealthBackgroundSync.performBackgroundSync()
        }
    }
}
