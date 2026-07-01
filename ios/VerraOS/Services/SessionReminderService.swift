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

        let fireDate = sessionDate(for: session).addingTimeInterval(-Double(minutesBefore * 60))
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming session"
        content.body = "See \(session.clientName) at \(Session.display(session.startMinutes)) · \(session.location.isEmpty ? session.focus : session.location)"
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

    private static func sessionDate(for session: Session) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: Date())
        components.day = session.dayOfMonth
        components.hour = session.startMinutes / 60
        components.minute = session.startMinutes % 60
        return calendar.date(from: components) ?? Date()
    }
}
