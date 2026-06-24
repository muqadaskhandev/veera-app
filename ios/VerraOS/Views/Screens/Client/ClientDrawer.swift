//
//  ClientDrawer.swift
//  VerraOS
//
//  Slide-in account sidebar for the client experience, mirroring the trainer's
//  ProfileDrawer style: avatar header, grouped rows, and a destructive Delete
//  Account row with confirmation.
//

import SwiftUI

struct ClientDrawer: View {
    let name: String
    let initials: String
    let email: String
    let version: String
    let onClose: () -> Void
    var onEditDetails: () -> Void = {}
    var onManageWearables: () -> Void = {}
    var onViewTrainer: () -> Void = {}
    var onAppSettings: () -> Void = {}
    var onHelp: () -> Void = {}
    var onLegal: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    section(title: "Account") {
                        ClientDrawerRow(icon: "person", label: "Edit Details", action: onEditDetails)
                        ClientDrawerRow(icon: "applewatch", label: "Manage Wearables", action: onManageWearables)
                        ClientDrawerRow(icon: "figure.strengthtraining.traditional", label: "Your Trainer", action: onViewTrainer)
                        ClientDrawerRow(icon: "slider.horizontal.3", label: "App Settings", action: onAppSettings)
                    }
                    divider
                    section(title: "Support") {
                        ClientDrawerRow(icon: "questionmark.circle", label: "Help & Support", action: onHelp)
                        ClientDrawerRow(icon: "doc.text", label: "Legal Documents", trailing: "arrow.up.right", action: onLegal)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }

            Spacer(minLength: 0)

            Text(version)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Color.background)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                        .frame(width: 36, height: 36)
                        .background(Theme.Color.surface, in: Circle())
                        .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close menu")
            }

            Circle()
                .fill(Theme.Color.ink)
                .frame(width: 72, height: 72)
                .overlay(
                    Text(initials)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accent)
                )
                .overlay(Circle().stroke(Theme.Color.accent, lineWidth: 2).padding(-4))

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text(email.isEmpty ? "Client" : email)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
            }
        }
    }

    // MARK: Sections

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.Color.inkFaint)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.bottom, 6)
            content()
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Color.hairline)
            .frame(height: 1)
            .padding(.horizontal, Theme.Spacing.sm)
    }
}

/// A non-navigating row that hosts the KG / lbs segmented toggle.
private struct ClientUnitRow: View {
    let unit: WeightUnit
    let onSelect: (WeightUnit) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "scalemass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Color.ink)
                .frame(width: 26)

            Text("Units")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Color.ink)

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                ForEach(WeightUnit.allCases) { option in
                    let isActive = unit == option
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { onSelect(option) }
                    } label: {
                        Text(option.short.uppercased())
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.inkMuted)
                            .frame(width: 40)
                            .padding(.vertical, 7)
                            .background(isActive ? Theme.Color.accent : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Theme.Color.surfaceMuted, in: Capsule())
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 9)
    }
}

/// A single tappable row inside the client drawer.
private struct ClientDrawerRow: View {
    let icon: String
    let label: String
    var trailing: String? = nil
    var isDestructive: Bool = false
    var action: () -> Void = {}

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isDestructive ? Theme.Color.danger : Theme.Color.ink)
                    .frame(width: 26)

                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isDestructive ? Theme.Color.danger : Theme.Color.ink)

                Spacer(minLength: 0)

                if let trailing {
                    Image(systemName: trailing)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(pressed ? Theme.Color.surfaceMuted : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.1)) { pressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { pressed = false } }
        )
    }
}
