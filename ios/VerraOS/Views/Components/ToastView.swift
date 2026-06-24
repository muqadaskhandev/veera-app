//
//  ToastView.swift
//  VerraOS
//

import SwiftUI

/// Lightweight confirmation toast payload.
struct ToastData: Identifiable, Equatable {
    let id = UUID()
    let message: String
    var icon: String = "checkmark.circle.fill"
}

/// A pill toast that slides up from the bottom and auto-dismisses.
private struct ToastView: View {
    let data: ToastData

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: data.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Color.accent)
            Text(data.message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.background)
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Theme.Color.ink, in: Capsule())
        .shadow(color: Color(hex: 0x1A1A17).opacity(0.22), radius: 18, x: 0, y: 10)
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: ToastData?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                ToastView(data: toast)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(2.4))
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            self.toast = nil
                        }
                    }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: toast)
    }
}

extension View {
    /// Presents a transient toast pinned to the bottom of the view.
    func toast(_ toast: Binding<ToastData?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
