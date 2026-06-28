//
//  SettingsHubView.swift
//  VerraOS
//

import SwiftUI

/// Hub listing the three settings areas: Calendar, Notifications, Security.
/// Presented as its own NavigationStack from the drawer's "App Settings" row.
struct SettingsHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TrainerStore.self) private var trainer

    var onLogOut: () -> Void = {}
    var onDeleteAccount: () -> Void = {}

    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.sm) {
                    NavigationLink {
                        CalendarSyncSettingsView()
                    } label: {
                        SettingsRow(
                            icon: "calendar",
                            tint: Color(hex: 0x4285F4),
                            title: "Calendar Integration",
                            subtitle: "Connect Google or Apple Calendar"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NotificationPreferencesView()
                    } label: {
                        SettingsRow(
                            icon: "bell.badge.fill",
                            tint: Color(hex: 0xF2A93C),
                            title: "Notification Preferences",
                            subtitle: "Alerts, categories & quiet hours"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SecurityView(onLogOut: {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onLogOut() }
                        })
                    } label: {
                        SettingsRow(
                            icon: "lock.fill",
                            tint: Theme.Color.ink,
                            title: "Security",
                            subtitle: "Password, biometrics & sign out"
                        )
                    }
                    .buttonStyle(.plain)

                    unitsCard

                    logOutCard
                        .padding(.top, Theme.Spacing.md)

                    dangerZone
                        .padding(.top, 40)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 40)
            }
            .background(Theme.Color.background)
            .navigationTitle("Settings")
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

    private var logOutCard: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onLogOut() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.Color.inkMuted.opacity(0.14)).frame(width: 44, height: 44)
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                }
                Text("Log Out")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
            .cardShadow()
        }
        .buttonStyle(.plain)
    }

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DANGER ZONE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.Color.danger.opacity(0.8))
                .padding(.horizontal, 4)
            Button {
                confirmingDelete = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Theme.Color.danger.opacity(0.14)).frame(width: 44, height: 44)
                        Image(systemName: "trash.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.Color.danger)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete Account")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Color.danger)
                        Text("Permanently remove your account and data")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Color.inkMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Color.danger.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.danger.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDeleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your account and all client data. This can't be undone.")
        }
    }

    private var unitsCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(hex: 0x57C77B).opacity(0.14)).frame(width: 44, height: 44)
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x57C77B))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Units")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Text("Weight measurement unit")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
            }
            Spacer(minLength: 8)
            unitToggle
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow()
    }

    private var unitToggle: some View {
        HStack(spacing: 3) {
            ForEach(WeightUnit.allCases) { unit in
                let isActive = trainer.units == unit
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { trainer.units = unit }
                } label: {
                    Text(unit.short.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.inkMuted)
                        .frame(width: 46)
                        .padding(.vertical, 8)
                        .background(isActive ? Theme.Color.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.Color.surfaceMuted, in: Capsule())
    }
}

/// A tappable settings hub row with an icon, title, subtitle, and chevron.
struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.14)).frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow()
    }
}
