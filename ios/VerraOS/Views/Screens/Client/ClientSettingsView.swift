//
//  ClientSettingsView.swift
//  VerraOS
//
//  The client's App Settings screen: unit preference up top, Log Out on its own,
//  and a clearly separated Delete Account danger zone so the two can't be tapped
//  by mistake. Mirrors the trainer's settings layout for consistency.
//

import SwiftUI

struct ClientSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let unit: WeightUnit
    var onSelectUnit: (WeightUnit) -> Void = { _ in }
    var onLogOut: () -> Void = {}
    var onDeleteAccount: () -> Void = {}

    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.sm) {
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
            ForEach(WeightUnit.allCases) { option in
                let isActive = unit == option
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { onSelectUnit(option) }
                } label: {
                    Text(option.short.uppercased())
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
            Text("This permanently removes your account and data. This can't be undone.")
        }
    }
}
