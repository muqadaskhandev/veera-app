//
//  NotificationPreferencesView.swift
//  VerraOS
//

import SwiftUI

/// Master switch, per-category toggles, Activity granularity, and Quiet Hours.
/// Pushed from the Settings hub. Bound directly to the persistent TrainerStore.
struct NotificationPreferencesView: View {
    @Environment(TrainerStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                masterCard(enabled: $store.profile.notificationsEnabled)

                Group {
                    categorySection(
                        money: $store.profile.notifyMoney,
                        schedule: $store.profile.notifySchedule,
                        activity: $store.profile.notifyActivity
                    )
                    if store.profile.notifyActivity {
                        activityModeSection(mode: $store.profile.activityMode)
                    }
                    quietHoursSection(
                        enabled: $store.profile.quietHoursEnabled,
                        start: $store.profile.quietStartMinutes,
                        end: $store.profile.quietEndMinutes
                    )
                }
                .opacity(store.profile.notificationsEnabled ? 1 : 0.4)
                .disabled(!store.profile.notificationsEnabled)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, 44)
            .animation(.spring(response: 0.34, dampingFraction: 0.85), value: store.profile.notifyActivity)
            .animation(.easeInOut(duration: 0.2), value: store.profile.notificationsEnabled)
        }
        .background(Theme.Color.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.Color.accent)
    }

    // MARK: Master

    private func masterCard(enabled: Binding<Bool>) -> some View {
        Toggle(isOn: enabled) {
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
                    Text(enabled.wrappedValue ? "You'll be alerted in the app." : "All alerts are paused.")
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

    // MARK: Categories

    private func categorySection(money: Binding<Bool>, schedule: Binding<Bool>, activity: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Pick Your Alerts")
            VStack(spacing: 0) {
                prefToggle(isOn: money, title: "Money", subtitle: "Payments & low session balance", icon: "dollarsign.circle.fill", tint: Color(hex: 0x57C77B))
                hairline
                prefToggle(isOn: schedule, title: "Schedule", subtitle: "Cancellations & moved sessions", icon: "calendar", tint: Color(hex: 0x6FB3F2))
                hairline
                prefToggle(isOn: activity, title: "Activity", subtitle: "Client workout completions", icon: "figure.run", tint: Color(hex: 0xF2A93C))
            }
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    private func activityModeSection(mode: Binding<ActivityAlertMode>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Activity Detail")
            VStack(spacing: 0) {
                ForEach(Array(ActivityAlertMode.allCases.enumerated()), id: \.element.id) { index, option in
                    Button {
                        mode.wrappedValue = option
                    } label: {
                        HStack {
                            Text(option.label)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.Color.ink)
                            Spacer()
                            Image(systemName: mode.wrappedValue == option ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(mode.wrappedValue == option ? Theme.Color.accentInk : Theme.Color.inkFaint)
                                .background(
                                    mode.wrappedValue == option
                                        ? Circle().fill(Theme.Color.accent).frame(width: 19, height: 19)
                                        : nil
                                )
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, 15)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < ActivityAlertMode.allCases.count - 1 { hairline }
                }
            }
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    private func quietHoursSection(enabled: Binding<Bool>, start: Binding<Int>, end: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Quiet Hours")
            VStack(spacing: 0) {
                prefToggle(isOn: enabled, title: "Quiet Hours", subtitle: "Silence alerts overnight", icon: "moon.fill", tint: Color(hex: 0x7B6FE0))
                if enabled.wrappedValue {
                    hairline
                    timeRow(label: "From", minutes: start)
                    hairline
                    timeRow(label: "To", minutes: end)
                }
            }
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: enabled.wrappedValue)
        }
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

    private func prefToggle(isOn: Binding<Bool>, title: String, subtitle: String, icon: String, tint: Color) -> some View {
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

    private var hairline: some View {
        Rectangle().fill(Theme.Color.hairline).frame(height: 1).padding(.horizontal, Theme.Spacing.md)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Color.inkFaint)
    }

    // MARK: Time helpers

    private static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}
