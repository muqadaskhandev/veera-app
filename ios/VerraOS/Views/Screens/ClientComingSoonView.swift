//
//  ClientComingSoonView.swift
//  VerraOS
//

import SwiftUI

/// Themed placeholder for the not-yet-built Client experience. Offers a clear
/// way back to the welcome screen so roles can be switched while testing.
struct ClientComingSoonView: View {
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Theme.Color.surface)
                        .frame(width: 104, height: 104)
                        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Theme.Color.hairline, lineWidth: 1))
                        .cardShadow()
                    Image(systemName: "figure.run")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                    Circle()
                        .fill(Theme.Color.accent)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.Color.accentInk)
                        )
                        .offset(x: 44, y: -44)
                }

                VStack(spacing: 10) {
                    Text("Client Experience")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text("Your training plans, progress, and chat with your coach will live here soon.")
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

                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 15, weight: .bold))
                        Text("Back to Welcome")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Theme.Color.ink)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(Theme.Color.ink.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
