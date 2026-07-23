import Foundation

/// Shared calendar helpers for the trainer and client schedule screens.
enum ScheduleCalendar {
    private static let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Monday-based week containing `anchor`.
    static func week(containing anchor: Date, calendar: Calendar = .current) -> [Date] {
        var cal = calendar
        cal.firstWeekday = 2
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)) else {
            return []
        }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    static func weekdayLabel(for date: Date, calendar: Calendar = .current) -> String {
        let weekday = calendar.component(.weekday, from: date)
        return weekdayLabels[(weekday + 5) % 7]
    }

    static func dayOfMonth(for date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.day, from: date)
    }

    static func date(in monthAnchor: Date, day: Int, calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month], from: monthAnchor)
        components.day = day
        return calendar.date(from: components)
    }

    /// Sessions whose wall-clock day matches the civil day the user tapped.
    static func sessions(_ sessions: [Session], on date: Date, calendar: Calendar = .current) -> [Session] {
        let selectedDay = calendar.startOfDay(for: date)
        return sessions
            .filter { session in
                calendar.startOfDay(for: session.scheduledAt) == selectedDay
            }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Sessions whose session-zone civil day falls in the Monday-based week strip.
    static func sessionsInWeek(_ sessions: [Session], containing anchor: Date = Date(), calendar: Calendar = .current) -> [Session] {
        let weekDays = week(containing: anchor, calendar: calendar)
        guard let first = weekDays.first, let last = weekDays.last else { return [] }
        let start = calendar.startOfDay(for: first)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else {
            return []
        }
        return sessions.filter { session in
            // Match the week strip with the viewer's calendar so volume/dots stay in sync
            // with the days the trainer is looking at (avoids TZ component mismatches).
            let day = calendar.startOfDay(for: session.scheduledAt)
            return day >= start && day < end
        }
    }
}
