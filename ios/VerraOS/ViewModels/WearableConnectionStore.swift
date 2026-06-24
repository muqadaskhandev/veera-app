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
        case .appleHealth: return "Sleep · Heart · Activity · Workouts"
        case .appleWatch: return "Heart rate · Calories · Rings"
        case .whoop: return "Strain · Recovery · HRV"
        case .garmin: return "Steps · Sleep · Stress"
        case .fitbit: return "Steps · Sleep · Resting HR"
        case .oura: return "Sleep · Readiness · HRV"
        }
    }
}

/// Owns the client's wearable connection state for the demo session: which
/// devices are linked and when data was last synced. Persisted to UserDefaults
/// so connections survive app launches.
@Observable
final class WearableConnectionStore {
    private static let connectedKey = "verra.client.wearables.connected.v1"
    private static let syncedKey = "verra.client.wearables.lastSynced.v1"

    var connected: Set<WearableDevice> {
        didSet { persist() }
    }
    var lastSynced: Date?
    var isSyncing: Bool = false

    init() {
        if let raw = UserDefaults.standard.array(forKey: Self.connectedKey) as? [String] {
            connected = Set(raw.compactMap(WearableDevice.init(rawValue:)))
        } else {
            connected = []
        }
        if let stored = UserDefaults.standard.object(forKey: Self.syncedKey) as? Date {
            lastSynced = stored
        } else {
            lastSynced = nil
        }
    }

    var hasAnyConnection: Bool { !connected.isEmpty }

    func isConnected(_ device: WearableDevice) -> Bool {
        connected.contains(device)
    }

    /// Connects or disconnects a device, refreshing the synced timestamp on
    /// connect.
    func toggle(_ device: WearableDevice) {
        if connected.contains(device) {
            connected.remove(device)
            if connected.isEmpty { lastSynced = nil }
        } else {
            connected.insert(device)
            lastSynced = Date()
        }
    }

    /// Simulates pulling fresh data from connected devices and stamps the time.
    @MainActor
    func syncNow() async {
        guard hasAnyConnection, !isSyncing else { return }
        isSyncing = true
        try? await Task.sleep(for: .seconds(1.1))
        lastSynced = Date()
        isSyncing = false
        UserDefaults.standard.set(lastSynced, forKey: Self.syncedKey)
    }

    /// A friendly relative description of the last sync time.
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

    private func persist() {
        UserDefaults.standard.set(connected.map(\.rawValue), forKey: Self.connectedKey)
        UserDefaults.standard.set(lastSynced, forKey: Self.syncedKey)
    }
}
