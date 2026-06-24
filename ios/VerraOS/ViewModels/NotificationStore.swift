//
//  NotificationStore.swift
//  VerraOS
//

import SwiftUI

/// Owns the Notification Center feed: schedule reminders, cancellations,
/// low-balance warnings, payment confirmations, and new-message alerts.
/// Seeded with a realistic mix spanning Today and Earlier.
@Observable
final class NotificationStore {
    var notifications: [AppNotification]

    init(notifications: [AppNotification] = NotificationStore.seed()) {
        self.notifications = notifications
    }

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    var hasUnread: Bool { unreadCount > 0 }

    /// Alerts within the last 24h, newest first.
    var today: [AppNotification] {
        notifications.filter(\.isToday).sorted { $0.minutesAgo < $1.minutesAgo }
    }

    /// Older alerts, newest first.
    var earlier: [AppNotification] {
        notifications.filter { !$0.isToday }.sorted { $0.minutesAgo < $1.minutesAgo }
    }

    // MARK: Mutations

    func markAllRead() {
        for index in notifications.indices {
            notifications[index].isRead = true
        }
    }

    func markRead(_ id: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[index].isRead = true
    }

    func dismiss(_ id: UUID) {
        notifications.removeAll { $0.id == id }
    }

    // MARK: Seed

    static func seed() -> [AppNotification] {
        [
            AppNotification(
                category: .reminder,
                title: "Tomorrow's lineup",
                detail: "You have 5 sessions tomorrow starting at 8:00 AM.",
                minutesAgo: 35
            ),
            AppNotification(
                category: .newMessage,
                title: "New message from Maya",
                detail: "Sent a form-check video on her deadlift.",
                minutesAgo: 70
            ),
            AppNotification(
                category: .lowBalance,
                title: "Renewal needed",
                detail: "Mike Ross has 1 session left.",
                minutesAgo: 180
            ),
            AppNotification(
                category: .paymentLogged,
                title: "Package added",
                detail: "Success: 10-Pack added for Mike Ross.",
                minutesAgo: 185,
                isRead: true
            ),
            AppNotification(
                category: .cancellation,
                title: "Session cancelled",
                detail: "Sarah (Tuesday @ 2 PM) has been removed.",
                minutesAgo: 540
            ),
            AppNotification(
                category: .newMessage,
                title: "New message from Sarah",
                detail: "Sent a voice message.",
                minutesAgo: 1500,
                isRead: true
            ),
            AppNotification(
                category: .reminder,
                title: "Weekly recap",
                detail: "You completed 18 sessions this week. Nice work.",
                minutesAgo: 2880,
                isRead: true
            ),
            AppNotification(
                category: .paymentLogged,
                title: "Package added",
                detail: "Success: 20-Pack added for Aria Bennett.",
                minutesAgo: 4320,
                isRead: true
            ),
        ]
    }
}
