//
//  SkeletonBone.swift
//  VerraOS
//
//  Soft pulsing placeholder shapes used instead of ProgressView spinners
//  while lists and chat threads load.
//

import SwiftUI

/// A single pulsing bone block. Compose these into row / bubble skeletons.
struct SkeletonBone: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 6

    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Color.surfaceMuted)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .opacity(pulse ? 0.45 : 1)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: pulse
            )
            .onAppear { pulse = true }
    }
}

/// Inbox row placeholder matching `ConversationRow` layout.
struct ConversationRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonBone(width: 50, height: 50, cornerRadius: 25)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SkeletonBone(width: 120, height: 14, cornerRadius: 5)
                    Spacer(minLength: 6)
                    SkeletonBone(width: 36, height: 10, cornerRadius: 4)
                }
                SkeletonBone(height: 12, cornerRadius: 5)
                    .padding(.trailing, 40)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }
}

/// Chat bubble placeholders for the message stream.
struct ChatThreadSkeleton: View {
    var body: some View {
        VStack(spacing: 14) {
            bubble(outgoing: false, width: 180)
            bubble(outgoing: true, width: 140)
            bubble(outgoing: false, width: 210)
            bubble(outgoing: true, width: 160)
            bubble(outgoing: false, width: 120)
            bubble(outgoing: true, width: 190)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func bubble(outgoing: Bool, width: CGFloat) -> some View {
        HStack {
            if outgoing { Spacer(minLength: 48) }
            SkeletonBone(width: width, height: 44, cornerRadius: 18)
            if !outgoing { Spacer(minLength: 48) }
        }
    }
}

/// Several inbox row skeletons stacked for the Messages tab.
struct MessagesInboxSkeleton: View {
    var count: Int = 6

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { _ in
                ConversationRowSkeleton()
            }
        }
    }
}
