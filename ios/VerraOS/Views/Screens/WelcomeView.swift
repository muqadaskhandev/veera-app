//
//  WelcomeView.swift
//  VerraOS
//

import SwiftUI

/// First screen on launch. Plays a looping workout video behind a top-left
/// wordmark and a big centered tagline, then offers two role entry points.
struct WelcomeView: View {
    let onSelectTrainer: () -> Void
    let onSelectClient: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            // Video background with graceful black fallback.
            LoopingVideoView(resourceName: "gym_strength_training_loop", fileExtension: "mp4")
                .ignoresSafeArea()

            // Legibility scrim.
            LinearGradient(
                colors: [
                    .black.opacity(0.45),
                    .black.opacity(0.4),
                    .black.opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                logo
                    .padding(.top, 8)
                Spacer()
                tagline
                Spacer()
                buttons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 44)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) {
                appeared = true
            }
        }
    }

    // MARK: Logo (top-left)

    private var logo: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Theme.Color.accent)
                .frame(width: 10, height: 10)
            (
                Text("VERRA")
                    .foregroundStyle(.white)
                + Text("OS")
                    .foregroundStyle(Theme.Color.accent)
            )
            .font(.system(size: 24, weight: .black))
            .fontWidth(.condensed)
        }
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Tagline

    private var tagline: some View {
        (
            Text("The ")
                .foregroundStyle(.white)
            + Text("ultimate command center")
                .foregroundStyle(Theme.Color.accent)
            + Text(" for elite trainers")
                .foregroundStyle(.white)
        )
        .font(.system(size: 46, weight: .black))
        .fontWidth(.condensed)
        .textCase(.uppercase)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: 14) {
            EntryButton(title: "For Trainers", style: .primary, action: onSelectTrainer)
            EntryButton(title: "For Clients", style: .secondary, action: onSelectClient)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }
}

/// A large full-width pill entry button with primary (lime) and secondary (glass) styles.
private struct EntryButton: View {
    enum Style { case primary, secondary }

    let title: String
    let style: Style
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .black))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 19)
                .background(Capsule().fill(background))
                .overlay(Capsule().stroke(strokeColor, lineWidth: 1))
                .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    private var foreground: Color {
        style == .primary ? Theme.Color.accentInk : .white
    }

    private var background: Color {
        style == .primary ? Theme.Color.accent : Color.white.opacity(0.14)
    }

    private var strokeColor: Color {
        style == .primary ? .clear : .white.opacity(0.28)
    }
}
