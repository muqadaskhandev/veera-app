//
//  BottomTabBar.swift
//  VerraOS
//

import SwiftUI

/// Sticky bottom navigation with four evenly distributed tabs.
/// Active: filled/bold icon + dark colored label. Inactive: outlined icon + light grey.
struct BottomTabBar: View {
    let selected: NavTab
    let onSelect: (NavTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NavTab.allCases) { tab in
                TabItem(tab: tab, isActive: tab == selected) {
                    onSelect(tab)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            Theme.Color.surface
                .clipShape(.rect(topLeadingRadius: 26, topTrailingRadius: 26))
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Color.hairline)
                .frame(height: 1)
        }
        .shadow(color: Color(hex: 0x1A1A17).opacity(0.06), radius: 16, x: 0, y: -6)
    }
}

private struct TabItem: View {
    let tab: NavTab
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if isActive {
                        Capsule()
                            .fill(Theme.Color.accent)
                            .frame(width: 52, height: 32)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Image(systemName: isActive ? tab.symbolFilled : tab.symbol)
                        .font(.system(size: 19, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.inkFaint)
                }
                .frame(height: 32)

                Text(tab.label)
                    .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? Theme.Color.ink : Theme.Color.inkFaint)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }
}
