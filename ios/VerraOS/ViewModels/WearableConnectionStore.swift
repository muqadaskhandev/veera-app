//
//  WearableConnectionStore.swift
//  VerraOS
//

import SwiftUI

/// A wearable / health data source the client can connect to share data with
/// their trainer.
enum WearableDevice: String, CaseIterable, Identifiable {
    case appleHealth
    case appleWatch
    case whoop
    case garmin
    case fitbit
    case oura

    var id: String { rawValue }

    /// v1 integrations shown in the connect list.
    static var availableInV1: [WearableDevice] {
        [.appleHealth, .oura]
    }

    var apiProvider: String {
        switch self {
        case .appleHealth, .appleWatch: return "apple_health"
        case .oura: return "oura"
        case .whoop, .garmin, .fitbit: return rawValue
        }
    }

    var name: String {
        switch self {
        case .appleHealth: return "Apple Health"
        case .appleWatch: return "Apple Watch"
        case .whoop: return "Whoop"
        case .garmin: return "Garmin"
        case .fitbit: return "Fitbit"
        case .oura: return "Oura Ring"
        }
    }

    var icon: String {
        switch self {
        case .appleHealth: return "heart.fill"
        case .appleWatch: return "applewatch"
        case .whoop: return "bolt.heart.fill"
        case .garmin: return "location.north.circle.fill"
        case .fitbit: return "figure.run"
        case .oura: return "circle.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .appleHealth: return Color(hex: 0xFF2D55)
        case .appleWatch: return Theme.Color.ink
        case .whoop: return Color(hex: 0x2BB673)
        case .garmin: return Color(hex: 0x4C8DF5)
        case .fitbit: return Color(hex: 0x00B0B9)
        case .oura: return Color(hex: 0x7B61FF)
        }
    }

    /// Short summary of what the trainer will receive from this device.
    var permissionSummary: String {
        switch self {
        case .appleHealth: return "Sleep · Steps · Heart · Activity · Workouts"
        case .appleWatch: return "Heart rate · Calories · Rings"
        case .whoop: return "Strain · Recovery · HRV"
        case .garmin: return "Steps · Sleep · Stress"
        case .fitbit: return "Steps · Sleep · Resting HR"
        case .oura: return "Sleep · Readiness · HRV"
        }
    }

    var requiresHealthKit: Bool {
        self == .appleHealth
    }

    var requiresOuraOAuth: Bool {
        self == .oura
    }
}

/// Owns wearable connection state, HealthKit authorization, and server sync.
@Observable
final class WearableConnectionStore {
    private static let syncedKey = "verra.client.wearables.lastSynced.v1"

    var connected: Set<WearableDevice> = []
    var lastSynced: Date?
    var isSyncing = false
    var pendingAppleHealthConnect = false
    var lastSyncError: String?

    init() {
        if let stored = UserDefaults.standard.object(forKey: Self.syncedKey) as? Date {
            lastSynced = stored
        }
    }

    var hasAnyConnection: Bool { !connected.isEmpty }

    func isConnected(_ device: WearableDevice) -> Bool {
        connected.contains(device)
    }

    /// Loads connection state from the API after login.
    @MainActor
    func refreshFromServer() async {
        guard let token = AuthStore.accessToken else { return }
        do {
            let response = try await VerraAPI.fetchMyHealth(accessToken: token)
            connected = Set(response.connections.compactMap { dto in
                WearableDevice.availableInV1.first { $0.apiProvider == dto.provider }
            })
            if let latest = response.connections.compactMap(\.lastSyncedAt).max() {
                lastSynced = latest
                UserDefaults.standard.set(latest, forKey: Self.syncedKey)
            }
        } catch {
            // Offline — keep local state.
        }
    }

    /// Connects or disconnects a device.
    @MainActor
    func toggle(_ device: WearableDevice) async throws {
        guard WearableDevice.availableInV1.contains(device) else { return }

        if connected.contains(device) {
            try await disconnect(device)
        } else if device.requiresHealthKit {
            pendingAppleHealthConnect = true
        } else if device.requiresOuraOAuth {
            try await connectOura()
        } else {
            try await connect(device)
        }
    }

    @MainActor
    func confirmAppleHealthConnect() async throws {
        pendingAppleHealthConnect = false
        try await HealthKitService.requestAuthorization()
        HealthKitBackgroundService.start()
        try await connect(.appleHealth)
    }

    @MainActor
    func cancelAppleHealthConnect() {
        pendingAppleHealthConnect = false
    }

    @MainActor
    private func connectOura() async throws {
        guard let token = AuthStore.accessToken else { return }
        try await OuraAuthService.connect(accessToken: token)
        connected.insert(.oura)
        lastSynced = Date()
        persistLastSynced()
    }

    @MainActor
    private func connect(_ device: WearableDevice) async throws {
        guard let token = AuthStore.accessToken else { return }
        _ = try await VerraAPI.connectHealthProvider(provider: device.apiProvider, accessToken: token)
        connected.insert(device)
        lastSynced = Date()
        persistLastSynced()
    }

    @MainActor
    private func disconnect(_ device: WearableDevice) async throws {
        guard let token = AuthStore.accessToken else { return }
        try await VerraAPI.disconnectHealthProvider(provider: device.apiProvider, accessToken: token)
        connected.remove(device)
        if connected.isEmpty {
            lastSynced = nil
            UserDefaults.standard.removeObject(forKey: Self.syncedKey)
        }
    }

    /// Pulls data from connected providers and uploads to the API.
    @MainActor
    func syncNow(healthData: HealthDataStore) async {
        guard hasAnyConnection, !isSyncing else { return }
        guard let token = AuthStore.accessToken else { return }

        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            var latestResponse: HealthMeResponse?

            if isConnected(.appleHealth) {
                let daily = try await HealthKitService.fetchDailyMetrics(days: 30)
                latestResponse = try await VerraAPI.syncHealth(
                    provider: WearableDevice.appleHealth.apiProvider,
                    metrics: daily.map { $0.asSyncInput() },
                    accessToken: token
                )
            }

            if isConnected(.oura) {
                latestResponse = try await VerraAPI.syncOura(accessToken: token)
            }

            if let latestResponse {
                healthData.metrics = latestResponse.metrics.sorted { $0.date < $1.date }
                healthData.connections = latestResponse.connections
                lastSynced = Date()
                persistLastSynced()
                HealthBackgroundSync.scheduleNextRefresh()
            }
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    var lastSyncedLabel: String {
        guard let lastSynced else { return "Not synced yet" }
        let seconds = Int(Date().timeIntervalSince(lastSynced))
        if seconds < 60 { return "Synced just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "Synced \(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "Synced \(hours)h ago" }
        return "Synced \(lastSynced.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func persistLastSynced() {
        UserDefaults.standard.set(lastSynced, forKey: Self.syncedKey)
    }
}
