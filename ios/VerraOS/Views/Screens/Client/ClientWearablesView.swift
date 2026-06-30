//
//  ClientWearablesView.swift
//  VerraOS
//
//  The client's wearables hub: connect / disconnect data sources, sync, and see
//  exactly what their trainer receives.
//

import SwiftUI

struct ClientWearablesView: View {
    let clientID: UUID

    @Environment(WearableConnectionStore.self) private var wearables
    @Environment(HealthDataStore.self) private var healthData

    @State private var toast: ToastData?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.Spacing.md) {
                syncCard
                devicesSection
                if !wearables.hasAnyConnection {
                    emptyState
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 110)
        }
        .background(Theme.Color.background)
        .toast($toast)
        .sheet(isPresented: Binding(
            get: { wearables.pendingAppleHealthConnect },
            set: { if !$0 { wearables.cancelAppleHealthConnect() } }
        )) {
            AppleHealthPermissionSheet(
                onConnect: {
                    Task {
                        do {
                            try await wearables.confirmAppleHealthConnect()
                            await wearables.syncNow(healthData: healthData)
                            toast = ToastData(message: "Apple Health connected", icon: "checkmark.circle.fill")
                        } catch {
                            toast = ToastData(message: error.localizedDescription, icon: "exclamationmark.circle.fill")
                        }
                    }
                },
                onCancel: { wearables.cancelAppleHealthConnect() }
            )
            .presentationDetents([.medium])
        }
        .task {
            await wearables.refreshFromServer()
            await healthData.refreshForClient(clientID: clientID, trainerView: false)
        }
    }

    // MARK: Sync status

    private var syncCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(wearables.hasAnyConnection ? Theme.Color.accent : Theme.Color.surfaceMuted)
                    .frame(width: 48, height: 48)
                Image(systemName: wearables.isSyncing ? "arrow.triangle.2.circlepath" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(wearables.hasAnyConnection ? Theme.Color.accentInk : Theme.Color.inkFaint)
                    .rotationEffect(.degrees(wearables.isSyncing ? 360 : 0))
                    .animation(wearables.isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: wearables.isSyncing)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(wearables.connected.count) connected")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.Color.background)
                Text(wearables.isSyncing ? "Syncing…" : wearables.lastSyncedLabel)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.Color.background.opacity(0.6))
            }
            Spacer(minLength: 8)
            syncButton
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .cardShadow()
    }

    private var syncButton: some View {
        Button {
            Task {
                await wearables.syncNow(healthData: healthData)
                if let error = wearables.lastSyncError {
                    toast = ToastData(message: error, icon: "exclamationmark.circle.fill")
                } else {
                    toast = ToastData(message: "Data synced", icon: "checkmark.circle.fill")
                }
            }
        } label: {
            Text(wearables.isSyncing ? "Syncing" : "Sync Now")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(wearables.hasAnyConnection ? Theme.Color.accentInk : Theme.Color.inkFaint)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(wearables.hasAnyConnection ? Theme.Color.accent : Theme.Color.surfaceMuted, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!wearables.hasAnyConnection || wearables.isSyncing)
    }

    // MARK: Devices

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONNECT A DEVICE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Theme.Color.inkFaint)
            VStack(spacing: 10) {
                ForEach(WearableDevice.availableInV1) { device in
                    DeviceRow(
                        device: device,
                        isConnected: wearables.isConnected(device)
                    ) {
                        Task {
                            do {
                                let wasConnected = wearables.isConnected(device)
                                try await wearables.toggle(device)
                                if !wasConnected, wearables.isConnected(device) {
                                    await wearables.syncNow(healthData: healthData)
                                }
                                toast = ToastData(
                                    message: wasConnected ? "\(device.name) disconnected" : "\(device.name) connected",
                                    icon: wasConnected ? "minus.circle.fill" : "checkmark.circle.fill"
                                )
                            } catch {
                                toast = ToastData(message: error.localizedDescription, icon: "exclamationmark.circle.fill")
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "applewatch.slash")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
            Text("No devices connected")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Color.ink)
            Text("Connect Apple Health or Oura above to start sharing your health data with your trainer.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

// MARK: - Apple Health permission sheet

private struct AppleHealthPermissionSheet: View {
    let onConnect: () -> Void
    let onCancel: () -> Void

    private let readItems = [
        ("moon.zzz.fill", "Sleep", "Nightly sleep duration"),
        ("figure.walk", "Steps", "Daily step count"),
        ("heart.fill", "Resting heart rate", "Daily resting HR average"),
        ("waveform.path.ecg", "HRV", "Heart rate variability"),
        ("flame.fill", "Active energy", "Calories burned through activity"),
        ("figure.run", "Workouts", "Workout sessions from Apple Watch and other apps"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.Color.hairline)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color(hex: 0xFF2D55).opacity(0.15)).frame(width: 56, height: 56)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFF2D55))
                }

                Text("Connect Apple Health")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)

                Text("Verra will read the following data to share daily summaries with your trainer. We never upload raw heartbeats.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    ForEach(readItems, id: \.1) { icon, title, subtitle in
                        HStack(spacing: 12) {
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xFF2D55))
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.Color.ink)
                                Text(subtitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.Color.inkMuted)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Not Now")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.Color.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.Color.surfaceMuted, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onConnect) {
                        Text("Allow Access")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.Color.accentInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.Color.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Theme.Color.background)
    }
}

// MARK: - Device row

private struct DeviceRow: View {
    let device: WearableDevice
    let isConnected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(device.tint.opacity(0.15)).frame(width: 46, height: 46)
                Image(systemName: device.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(device.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(device.name)
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                    if isConnected {
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: 0x57C77B)).frame(width: 6, height: 6)
                            Text("Connected")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Color(hex: 0x3F9E5C))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: 0x57C77B).opacity(0.14), in: Capsule())
                    }
                }
                Text(device.permissionSummary)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button(action: action) {
                Text(isConnected ? "Disconnect" : "Connect")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isConnected ? Theme.Color.inkMuted : Theme.Color.accentInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(isConnected ? Theme.Color.surfaceMuted : Theme.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(isConnected ? Theme.Color.accent.opacity(0.4) : Theme.Color.hairline, lineWidth: 1))
        .cardShadow(0.5)
    }
}
