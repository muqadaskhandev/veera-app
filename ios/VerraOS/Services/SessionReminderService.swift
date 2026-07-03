import Foundation
import UserNotifications

/// Schedules local push reminders for upcoming coaching sessions.
enum SessionReminderService {
    private static let center = UNUserNotificationCenter.current()

    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func scheduleReminder(for session: Session, minutesBefore: Int = 60) async throws {
        guard !session.isCompleted, !session.isSkipped, session.accent != .personal else { return }

        let granted = await requestAuthorization()
        guard granted else { return }

        let fireDate = session.scheduledAt.addingTimeInterval(-Double(minutesBefore * 60))
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = session.reminderTitle
        content.body = session.reminderBody
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationID(for: session.id),
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    static func rescheduleAll(for sessions: [Session], minutesBefore: Int) async {
        cancelAll(for: sessions)
        for session in sessions where !session.isCompleted && !session.isSkipped && session.accent != .personal {
            try? await scheduleReminder(for: session, minutesBefore: minutesBefore)
        }
    }

    static func cancelReminder(for sessionID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationID(for: sessionID)])
    }

    static func cancelAll(for sessions: [Session]) {
        let ids = sessions.map { notificationID(for: $0.id) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func notificationID(for sessionID: UUID) -> String {
        "verra.session.reminder.\(sessionID.uuidString)"
    }
}
