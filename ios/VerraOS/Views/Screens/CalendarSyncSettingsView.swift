//
//  CalendarSyncSettingsView.swift
//  VerraOS
//

import EventKit
import SwiftUI

/// Connect external (personal) calendars to the app, and choose import/export
/// directionality. Reached from the drawer's App Settings.
struct CalendarSyncSettingsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isConnectingApple = false
    @State private var alertMessage: String?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    statusSummary
                    linkSection
                    directionalitySection(importEvents: $store.importPersonalEvents, exportSessions: $store.exportSessions)
                    permissionNote
                    footnote
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 40)
            }
            .background(Theme.Color.background)
            .navigationTitle("Calendar Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                }
            }
            .alert("Calendar Sync", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .onChange(of: store.importPersonalEvents) { _, _ in
                store.saveCalendarPrefs()
                Task { await store.refreshCalendarData() }
            }
            .onChange(of: store.exportSessions) { _, _ in
                store.saveCalendarPrefs()
                Task { await store.refreshCalendarData() }
            }
        }
    }

    // MARK: Status summary

    private var statusSummary: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(store.isSynced ? Color(hex: 0x57C77B).opacity(0.16) : Theme.Color.surfaceMuted)
                    .frame(width: 52, height: 52)
                if store.isRefreshingCalendar {
                    ProgressView()
                } else {
                    Image(systemName: store.isSynced ? "checkmark.circle.fill" : "link.badge.plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(store.isSynced ? Color(hex: 0x57C77B) : Theme.Color.inkMuted)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(store.isSynced ? "Synced" : "Offline")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text(statusSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow()
    }

    private var statusSubtitle: String {
        if store.isSynced {
            if store.appleLinked { return "Apple Calendar connected." }
            return "Your calendars are connected."
        }
        return "Link Apple Calendar to import busy times and export sessions."
    }

    // MARK: Link accounts

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Link Account")
            VStack(spacing: Theme.Spacing.sm) {
                GoogleCalendarRow()
                AppleCalendarRow(
                    isLinked: store.appleLinked,
                    isConnecting: isConnectingApple,
                    onConnect: connectApple,
                    onDisconnect: disconnectApple
                )
            }
        }
    }

    private func connectApple() {
        isConnectingApple = true
        Task {
            let ok = await store.connectAppleCalendar()
            isConnectingApple = false
            if !ok {
                alertMessage = store.calendarSyncError ?? "Could not connect Apple Calendar."
            }
        }
    }

    private func disconnectApple() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            store.disconnectAppleCalendar()
        }
    }

    // MARK: Directionality

    private func directionalitySection(importEvents: Binding<Bool>, exportSessions: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Directionality")
            VStack(spacing: 0) {
                directionToggle(
                    isOn: importEvents,
                    title: "Import Personal Events",
                    subtitle: "Pull events like \"Dentist\" in as grey Busy Blocks.",
                    icon: "arrow.down.circle.fill",
                    tint: Color(hex: 0xB6B2A8)
                )
                Rectangle().fill(Theme.Color.hairline).frame(height: 1).padding(.horizontal, Theme.Spacing.md)
                directionToggle(
                    isOn: exportSessions,
                    title: "Export Client Sessions",
                    subtitle: "Push your sessions to your personal phone calendar.",
                    icon: "arrow.up.circle.fill",
                    tint: Color(hex: 0x6FB3F2)
                )
            }
            .tint(Theme.Color.accent)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
            .opacity(store.isSynced ? 1 : 0.5)
            .disabled(!store.isSynced)
        }
    }

    private func directionToggle(isOn: Binding<Bool>, title: String, subtitle: String, icon: String, tint: Color) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var permissionNote: some View {
        if let error = store.calendarSyncError {
            Text(error)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } else if store.appleLinked {
            Text(applePermissionLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private var applePermissionLabel: String {
        switch CalendarSyncService.authorizationStatus {
        case .fullAccess:
            return "Full calendar access granted."
        case .writeOnly:
            return "Write-only access — enable full access in Settings to import busy blocks."
        case .denied, .restricted:
            return "Calendar access denied. Open Settings → Verra → Calendars to allow access."
        case .notDetermined:
            return "Calendar permission not yet requested."
        default:
            return ""
        }
    }

    private var footnote: some View {
        Text("Connect Apple Calendar so personal appointments appear as busy blocks and coaching sessions stay in sync. Google Calendar support is coming soon.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.Color.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Color.inkFaint)
    }
}

// MARK: - Link rows

private struct GoogleCalendarRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: 0x4285F4).opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x4285F4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Google Calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Text("Coming soon")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
            }
            Spacer()
            Text("Soon")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Color.inkFaint)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Theme.Color.surfaceMuted, in: Capsule())
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .opacity(0.7)
    }
}

private struct AppleCalendarRow: View {
    let isLinked: Bool
    let isConnecting: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.Color.ink.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Text(isLinked ? "Connected" : "Not connected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isLinked ? Color(hex: 0x57C77B) : Theme.Color.inkMuted)
            }
            Spacer()
            Button {
                if isLinked { onDisconnect() } else { onConnect() }
            } label: {
                Group {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Text(isLinked ? "Disconnect" : "Connect")
                    }
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isLinked ? Theme.Color.inkMuted : Theme.Color.accentInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isLinked ? Theme.Color.surfaceMuted : Theme.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }
}
