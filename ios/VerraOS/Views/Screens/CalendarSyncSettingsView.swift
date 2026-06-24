//
//  CalendarSyncSettingsView.swift
//  VerraOS
//

import SwiftUI

/// Connect external (personal) calendars to the app, and choose import/export
/// directionality. Reached from the drawer's App Settings.
struct CalendarSyncSettingsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    statusSummary
                    linkSection(google: $store.googleLinked, apple: $store.appleLinked)
                    directionalitySection(importEvents: $store.importPersonalEvents, exportSessions: $store.exportSessions)
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
        }
    }

    // MARK: Status summary

    private var statusSummary: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(store.isSynced ? Color(hex: 0x57C77B).opacity(0.16) : Theme.Color.surfaceMuted)
                    .frame(width: 52, height: 52)
                Image(systemName: store.isSynced ? "checkmark.circle.fill" : "link.badge.plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(store.isSynced ? Color(hex: 0x57C77B) : Theme.Color.inkMuted)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(store.isSynced ? "Synced" : "Offline")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text(store.isSynced ? "Your calendars are connected." : "Link a calendar to start syncing.")
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

    // MARK: Link accounts

    private func linkSection(google: Binding<Bool>, apple: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Link Account")
            VStack(spacing: Theme.Spacing.sm) {
                LinkAccountRow(
                    title: "Google Calendar",
                    icon: "calendar",
                    tint: Color(hex: 0x4285F4),
                    isLinked: google
                )
                LinkAccountRow(
                    title: "Apple Calendar",
                    icon: "calendar",
                    tint: Theme.Color.ink,
                    isLinked: apple
                )
            }
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

    private var footnote: some View {
        Text("Connect your personal and work calendars so nothing double-books. Account connections are simulated in this build.")
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

/// A single connect/disconnect row for an external calendar provider.
private struct LinkAccountRow: View {
    let title: String
    let icon: String
    let tint: Color
    @Binding var isLinked: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Text(isLinked ? "Connected" : "Not connected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isLinked ? Color(hex: 0x57C77B) : Theme.Color.inkMuted)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { isLinked.toggle() }
            } label: {
                Text(isLinked ? "Disconnect" : "Connect")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isLinked ? Theme.Color.inkMuted : Theme.Color.accentInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(isLinked ? Theme.Color.surfaceMuted : Theme.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }
}
