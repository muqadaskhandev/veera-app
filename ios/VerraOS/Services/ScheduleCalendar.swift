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

    /// Sessions whose wall-clock day (in the session timezone) matches the
    /// civil day the user tapped on the strip (in the viewer calendar).
    static func sessions(_ sessions: [Session], on date: Date, calendar: Calendar = .current) -> [Session] {
        let selectedDay = calendar.dateComponents([.year, .month, .day], from: date)
        return sessions
            .filter { session in
                let sessionDay = session.displayCalendar.dateComponents(
                    [.year, .month, .day],
                    from: session.scheduledAt
                )
                return sessionDay.year == selectedDay.year
                    && sessionDay.month == selectedDay.month
                    && sessionDay.day == selectedDay.day
            }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Sessions whose session-zone civil day falls in the Monday-based week strip.
    static func sessionsInWeek(_ sessions: [Session], containing anchor: Date = Date(), calendar: Calendar = .current) -> [Session] {
        let week = week(containing: anchor, calendar: calendar)
        guard !week.isEmpty else { return [] }
        let selectedDays: Set<DateComponents> = Set(
            week.map { calendar.dateComponents([.year, .month, .day], from: $0) }
        )
        return sessions.filter { session in
            let sessionDay = session.displayCalendar.dateComponents(
                [.year, .month, .day],
                from: session.scheduledAt
            )
            return selectedDays.contains {
                $0.year == sessionDay.year && $0.month == sessionDay.month && $0.day == sessionDay.day
            }
        }
    }
}
