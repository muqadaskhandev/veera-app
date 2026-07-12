//
//  ClientNotificationPreferencesView.swift
//  VerraOS
//

import SwiftUI

/// Client-facing notification preferences: schedule, messages, activity, and quiet hours.
struct ClientNotificationPreferencesView: View {
    @State private var notificationsEnabled = true
    @State private var notifySchedule = true
    @State private var notifyMessages = true
    @State private var notifyActivity = true
    @State private var quietHoursEnabled = true
    @State private var quietStartMinutes = 22 * 60
    @State private var quietEndMinutes = 6 * 60
    @State private var isLoading = true
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.xl)
                } else {
                    masterCard

                    Group {
                        categorySection
                        quietHoursSection
                    }
                    .opacity(notificationsEnabled ? 1 : 0.4)
                    .disabled(!notificationsEnabled)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, 44)
            .animation(.easeInOut(duration: 0.2), value: notificationsEnabled)
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: quietHoursEnabled)
        }
        .background(Theme.Color.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.Color.accent)
        .task { await loadPreferences() }
        .onDisappear { saveTask?.cancel() }
    }

    // MARK: - Sections

    private var masterCard: some View {
        Toggle(isOn: boolBinding($notificationsEnabled)) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.Color.accent.opacity(0.2)).frame(width: 48, height: 48)
                    Image(systemName: "bell.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("All Notifications")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text(notificationsEnabled ? "You'll be alerted in the app." : "All alerts are paused.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
            }
        }
        .tint(Theme.Color.accent)
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow()
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Pick Your Alerts")
            VStack(spacing: 0) {
                prefToggle(
                    isOn: boolBinding($notifySchedule),
                    title: "Schedule",
                    subtitle: "Upcoming sessions & cancellations",
                    icon: "calendar",
                    tint: Color(hex: 0x6FB3F2)
                )
                hairline
                prefToggle(
                    isOn: boolBinding($notifyMessages),
                    title: "Messages",
                    subtitle: "New chats from your trainer",
                    icon: "bubble.left.and.bubble.right.fill",
                    tint: Color(hex: 0x57C77B)
                )
                hairline
                prefToggle(
                    isOn: boolBinding($notifyActivity),
                    title: "Activity",
                    subtitle: "Session credits & progress updates",
                    icon: "figure.run",
                    tint: Color(hex: 0xF2A93C)
                )
            }
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    private var quietHoursSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Quiet Hours")
            VStack(spacing: 0) {
                prefToggle(
                    isOn: boolBinding($quietHoursEnabled),
                    title: "Quiet Hours",
                    subtitle: "Silence alerts overnight",
                    icon: "moon.fill",
                    tint: Color(hex: 0x7B6FE0)
                )
                if quietHoursEnabled {
                    hairline
                    timeRow(label: "From", minutes: intBinding($quietStartMinutes))
                    hairline
                    timeRow(label: "To", minutes: intBinding($quietEndMinutes))
                }
            }
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    // MARK: - Rows

    private func prefToggle(
        isOn: Binding<Bool>,
        title: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
            }
        }
        .tint(Theme.Color.accent)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 13)
    }

    private func timeRow(label: String, minutes: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
            Spacer()
            DatePicker(
                "",
                selection: Binding(
                    get: { Self.date(fromMinutes: minutes.wrappedValue) },
                    set: { minutes.wrappedValue = Self.minutes(from: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 11)
    }

    private var hairline: some View {
        Rectangle().fill(Theme.Color.hairline).frame(height: 1).padding(.horizontal, Theme.Spacing.md)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Color.inkFaint)
    }

    // MARK: - Bindings that auto-save

    private func boolBinding(_ state: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { state.wrappedValue },
            set: { newValue in
                state.wrappedValue = newValue
                scheduleSave()
            }
        )
    }

    private func intBinding(_ state: Binding<Int>) -> Binding<Int> {
        Binding(
            get: { state.wrappedValue },
            set: { newValue in
                state.wrappedValue = newValue
                scheduleSave()
            }
        )
    }

    // MARK: - API

    @MainActor
    private func loadPreferences() async {
        guard let token = AuthStore.accessToken else {
            isLoading = false
            return
        }
        defer { isLoading = false }

        guard let prefs = try? await VerraAPI.fetchNotificationPreferences(accessToken: token) else { return }
        notificationsEnabled = prefs.notificationsEnabled
        notifySchedule = prefs.notifySchedule
        notifyMessages = prefs.notifyMessages
        notifyActivity = prefs.notifyActivity
        quietHoursEnabled = prefs.quietHoursEnabled
        quietStartMinutes = prefs.quietStartMinutes
        quietEndMinutes = prefs.quietEndMinutes
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await savePreferences()
        }
    }

    @MainActor
    private func savePreferences() async {
        guard let token = AuthStore.accessToken else { return }
        _ = try? await VerraAPI.updateNotificationPreferences(
            VerraAPI.UpdateNotificationPreferencesBody(
                notificationsEnabled: notificationsEnabled,
                notifySchedule: notifySchedule,
                notifyMessages: notifyMessages,
                notifyActivity: notifyActivity,
                quietHoursEnabled: quietHoursEnabled,
                quietStartMinutes: quietStartMinutes,
                quietEndMinutes: quietEndMinutes
            ),
            accessToken: token
        )
    }

    // MARK: - Time helpers

    private static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}
