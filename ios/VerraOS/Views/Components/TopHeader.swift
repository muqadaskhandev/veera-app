//
//  TopHeader.swift
//  VerraOS
//

import SwiftUI

/// Fixed top header: hamburger menu, dynamic page title, notification bell
/// with a red unread badge.
struct TopHeader: View {
    let title: String
    let hasUnread: Bool
    /// When false, the menu and bell controls are hidden (Schedule-only).
    let showsControls: Bool
    let onMenu: () -> Void
    let onBell: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if showsControls {
                HeaderButton(symbol: "line.3.horizontal", action: onMenu)
                    .accessibilityLabel("Open menu")
            }

            Spacer(minLength: 0)

            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: title)

            Spacer(minLength: 0)

            if showsControls {
                HeaderButton(symbol: "bell", action: onBell) {
                    if hasUnread {
                        Circle()
                            .fill(Theme.Color.danger)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Theme.Color.background, lineWidth: 2))
                            .offset(x: 7, y: -7)
                    }
                }
                .accessibilityLabel("Notifications")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 10)
        .background(Theme.Color.background)
    }
}

/// Circular tappable header control with an optional badge overlay.
private struct HeaderButton<Badge: View>: View {
    let symbol: String
    let action: () -> Void
    @ViewBuilder var badge: Badge

    @State private var pressed = false

    init(symbol: String, action: @escaping () -> Void, @ViewBuilder badge: () -> Badge = { EmptyView() }) {
        self.symbol = symbol
        self.action = action
        self.badge = badge()
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
                .frame(width: 44, height: 44)
                .background(Theme.Color.surface, in: Circle())
                .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
                .overlay(alignment: .topTrailing) { badge }
                .scaleEffect(pressed ? 0.9 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.18)) { pressed = false } }
        )
    }
}
