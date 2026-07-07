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

    /// When true, hides the Done button (used for the client Alerts tab).
    var embeddedInTab: Bool = false

    @State private var selectedNotification: AppNotification?

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
                if !embeddedInTab {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.ink)
                    }
                }
                ToolbarItem(placement: embeddedInTab ? .topBarLeading : .topBarTrailing) {
                    Button("Mark all read") {
                        Task {
                            await store.markAllReadOnServer()
                        }
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(store.hasUnread ? Theme.Color.ink : Theme.Color.inkFaint)
                    .disabled(!store.hasUnread)
                }
            }
            .task {
                await store.refreshFromServer()
            }
            .sheet(item: $selectedNotification) { item in
                NotificationDetailSheet(
                    item: item,
                    onMarkRead: {
                        store.markRead(item.id)
                    }
                )
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
                    Button {
                        selectedNotification = item
                        if !item.isRead {
                            store.markRead(item.id)
                        }
                    } label: {
                        NotificationRow(item: item)
                    }
                    .buttonStyle(.plain)
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

            Text(embeddedInTab
                 ? "Session updates, package credits, and messages from your trainer appear here."
                 : "Session reminders, payments, and new messages will show up here.")
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
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.category.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(item.category.tint)
                    .frame(width: 42, height: 42)
                    .background(item.category.fill, in: Circle())

                if !item.isRead {
                    Circle()
                        .fill(Color(hex: 0x57C77B))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Theme.Color.surface, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(item.title)
                        .font(.system(size: 15, weight: item.isRead ? .semibold : .bold, design: .rounded))
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
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(item.isRead ? Theme.Color.surface : Theme.Color.accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(item.isRead ? Theme.Color.hairline : Color(hex: 0x57C77B).opacity(0.35), lineWidth: 1)
        )
        .cardShadow(item.isRead ? 0.4 : 0.8)
    }
}

private struct NotificationDetailSheet: View {
    let item: AppNotification
    let onMarkRead: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: item.category.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(item.category.tint)
                            .frame(width: 52, height: 52)
                            .background(item.category.fill, in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Color.ink)
                            Text(item.timeLabel)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.Color.inkMuted)
                        }
                    }

                    Text(item.detail)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Color.background)
            .navigationTitle("Notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .onAppear {
                onMarkRead()
            }
        }
        .presentationDetents([.medium, .large])
    }
}
