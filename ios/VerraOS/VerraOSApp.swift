//
//  VerraOSApp.swift
//  VerraOS
//

import SwiftUI

@main
struct VerraOSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .backgroundTask(.appRefresh(HealthBackgroundSync.taskIdentifier)) {
            _ = await HealthBackgroundSync.performBackgroundSync()
        }
    }
}
