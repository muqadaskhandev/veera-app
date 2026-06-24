//
//  PlaceholderView.swift
//  VerraOS
//

import SwiftUI

/// Elegant "coming soon" state for tabs not yet built out. Keeps the shell
/// feeling intentional rather than empty while screens are added one by one.
struct PlaceholderView: View {
    let tab: NavTab

    private var subtitle: String {
        switch tab {
        case .clients: return "Your roster, intake forms, and client progress will live here."
        case .messages: return "Direct conversations with every client, all in one inbox."
        case .financials: return "Revenue, payouts, and package tracking at a glance."
        case .schedule: return ""
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Theme.Color.surface)
                    .frame(width: 96, height: 96)
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.Color.hairline, lineWidth: 1))
                    .cardShadow()
                Image(systemName: tab.symbolFilled)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Circle()
                    .fill(Theme.Color.accent)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.accentInk)
                    )
                    .offset(x: 40, y: -40)
            }

            VStack(spacing: 8) {
                Text(tab.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Text("COMING SOON")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.Color.inkMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.Color.surfaceMuted, in: Capsule())

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
