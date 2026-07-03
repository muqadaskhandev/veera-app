//
//  CalendarSyncSettingsView.swift
//  VerraOS
//

import EventKit
import SwiftUI
import UIKit

/// Connect external (personal) calendars to the app, and choose import/export
/// directionality. Reached from the drawer's App Settings.
struct CalendarSyncSettingsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isConnectingApple = false
    @State private var isConnectingGoogle = false
    @State private var alertMessage: String?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    statusSummary
                    linkSection
                    directionalitySection(importEvents: $store.importPersonalEvents, exportSessions: $store.exportSessions)
                    remindersSection(
                        reminderMinutes: $store.calendarReminderMinutesBefore,
                        useDedicatedCalendar: $store.useDedicatedVerraCalendar
                    )
                    conflictSection(blockConflicts: $store.blockConflictsOnSave)
                    permissionNote
                    if CalendarSyncService.authorizationStatus == .denied || CalendarSyncService.authorizationStatus == .restricted {
                        openSettingsButton
                    }
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
            .onChange(of: store.exportSessions) { _, enabled in
                store.saveCalendarPrefs()
                if enabled {
                    Task { await store.exportSessionsToExternalCalendars() }
                }
            }
            .onChange(of: store.calendarReminderMinutesBefore) { _, _ in
                store.saveCalendarPrefs()
                Task {
                    await store.exportSessionsToExternalCalendars()
                    await SessionReminderService.rescheduleAll(for: store.sessions, minutesBefore: store.calendarReminderMinutesBefore)
                }
            }
            .onChange(of: store.blockConflictsOnSave) { _, _ in
                store.saveCalendarPrefs()
            }
            .onChange(of: store.useDedicatedVerraCalendar) { _, _ in
                store.saveCalendarPrefs()
                if store.useDedicatedVerraCalendar {
                    try? CalendarSyncService.ensureVerraCalendar()
                }
                Task { await store.exportSessionsToExternalCalendars() }
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
            switch (store.googleLinked, store.appleLinked) {
            case (true, true): return "Google and Apple Calendar connected."
            case (true, false): return "Google Calendar connected."
            case (false, true): return "Apple Calendar connected."
            default: return "Your calendars are connected."
            }
        }
        return "Link Google or Apple Calendar to import busy times and export sessions."
    }

    // MARK: Link accounts

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Link Account")
            VStack(spacing: Theme.Spacing.sm) {
                GoogleCalendarRow(
                    isLinked: store.googleLinked,
                    isConnecting: isConnectingGoogle,
                    onConnect: connectGoogle,
                    onDisconnect: disconnectGoogle
                )
                AppleCalendarRow(
                    isLinked: store.appleLinked,
                    isConnecting: isConnectingApple,
                    onConnect: connectApple,
                    onDisconnect: disconnectApple
                )
            }
        }
    }

    private func connectGoogle() {
        isConnectingGoogle = true
        Task {
            let ok = await store.connectGoogleCalendar()
            isConnectingGoogle = false
            if !ok {
                alertMessage = store.calendarSyncError ?? "Could not connect Google Calendar."
            }
        }
    }

    private func disconnectGoogle() {
        Task {
            await store.disconnectGoogleCalendar()
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

    // MARK: Reminders

    private func remindersSection(reminderMinutes: Binding<Int>, useDedicatedCalendar: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Reminders")
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remind me before sessions")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Color.ink)
                        Text("Sets calendar alarms and local push reminders.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Color.inkMuted)
                    }
                    Spacer()
                    Picker("", selection: reminderMinutes) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 14)

                Rectangle().fill(Theme.Color.hairline).frame(height: 1).padding(.horizontal, Theme.Spacing.md)

                Toggle(isOn: useDedicatedCalendar) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Verra Sessions calendar")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Color.ink)
                        Text("Exports to a dedicated calendar instead of your default.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Color.inkMuted)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 14)
            }
            .tint(Theme.Color.accent)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
            .opacity(store.isSynced ? 1 : 0.5)
            .disabled(!store.isSynced)
        }
    }

    // MARK: Conflicts

    private func conflictSection(blockConflicts: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Conflicts")
            Toggle(isOn: blockConflicts) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Block overlapping appointments")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                    Text("Prevent saving when a session overlaps another session or imported personal event.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.Color.accent)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 14)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    private var openSettingsButton: some View {
        Button {
            if let url = CalendarSyncService.openSettingsURL() {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack {
                Image(systemName: "gear")
                Text("Open iOS Settings")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
            return "Full calendar access granted. Personal events refresh automatically when your calendar changes."
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
        Text("Connect Google or Apple Calendar so personal appointments appear as busy blocks and coaching sessions stay in sync with reminders.")
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
    let isLinked: Bool
    let isConnecting: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

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
