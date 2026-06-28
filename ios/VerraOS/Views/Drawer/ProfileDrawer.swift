//
//  ProfileDrawer.swift
//  VerraOS
//

import SwiftUI

/// Slide-in navigation drawer presented from the left edge.
/// Header with avatar + name + "View Profile", three grouped menu sections
/// separated by hairline dividers, and a version footer.
struct ProfileDrawer: View {
    let profile: TrainerProfile
    let version: String
    let onClose: () -> Void
    var onEditProfile: () -> Void = {}
    var onAppSettings: () -> Void = {}
    var onLegal: () -> Void = {}
    var onHelp: () -> Void = {}
    var onLogOut: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    section(title: "Profile") {
                        DrawerRow(icon: "person", label: "Edit Profile", action: onEditProfile)
                        DrawerRow(icon: "slider.horizontal.3", label: "App Settings", action: onAppSettings)
                    }
                    divider
                    section(title: "Admin") {
                        DrawerRow(icon: "doc.text", label: "Legal Documents", trailing: "arrow.up.right", action: onLegal)
                        DrawerRow(icon: "questionmark.circle", label: "Help & Support", action: onHelp)
                    }
                    divider
                    section(title: "Session") {
                        DrawerRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            label: "Log Out",
                            isDestructive: true,
                            action: onLogOut
                        )
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

            avatar

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text(profile.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
            }

            Button(action: onEditProfile) {
                HStack(spacing: 6) {
                    Text("View Profile")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.Color.accentInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var avatar: some View {
        Group {
            if let data = profile.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Theme.Color.ink)
                    .overlay(
                        Text(profile.initials)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.accent)
                    )
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Color.accent, lineWidth: 2).padding(-4))
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

/// A single tappable row inside the drawer.
private struct DrawerRow: View {
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
