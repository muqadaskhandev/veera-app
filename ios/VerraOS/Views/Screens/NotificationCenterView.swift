//
//  NotificationCenterView.swift
//  VerraOS
//

import SwiftUI

/// Slide-up Notification Center presented from the top-bar bell. Shows alerts
/// grouped into Today / Earlier, with mark-all-read and swipe-to-dismiss.
struct NotificationCenterView: View {
    @Environment(NotificationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.notifications.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.Color.background)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") {
                        withAnimation(.easeInOut(duration: 0.25)) { store.markAllRead() }
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(store.hasUnread ? Theme.Color.ink : Theme.Color.inkFaint)
                    .disabled(!store.hasUnread)
                }
            }
        }
    }

    // MARK: List

    private var list: some View {
        List {
            section(title: "Today", items: store.today)
            section(title: "Earlier", items: store.earlier)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    @ViewBuilder
    private func section(title: String, items: [AppNotification]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    NotificationRow(item: item)
                        .listRowInsets(EdgeInsets(top: 5, leading: Theme.Spacing.md, bottom: 5, trailing: Theme.Spacing.md))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation { store.dismiss(item.id) }
                            } label: {
                                Label("Dismiss", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .tracking(0.6)
                    .listRowInsets(EdgeInsets(top: 14, leading: Theme.Spacing.md, bottom: 6, trailing: Theme.Spacing.md))
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
                .frame(width: 96, height: 96)
                .background(Theme.Color.surfaceMuted, in: Circle())

            Text("You're all caught up")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)

            Text("Session reminders, payments, and new messages will show up here.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.Color.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single alert row: colored category icon, title, detail, time, unread dot.
private struct NotificationRow: View {
    let item: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: item.category.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(item.category.tint)
                .frame(width: 42, height: 42)
                .background(item.category.fill, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Spacer(minLength: 0)
                    Text(item.timeLabel)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Color.inkFaint)
                }

                Text(item.detail)
                    .font(.system(size: 13.5, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !item.isRead {
                Circle()
                    .fill(Theme.Color.accent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(item.isRead ? Theme.Color.surface : Theme.Color.accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.Color.hairline, lineWidth: 1)
        )
        .cardShadow(item.isRead ? 0.4 : 0.8)
    }
}
