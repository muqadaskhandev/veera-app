//
//  Session.swift
//  VerraOS
//

import SwiftUI

/// A single coaching session on the trainer's schedule.
struct Session: Identifiable {
    let id: UUID
    var clientID: UUID?
    var clientName: String
    var focus: String
    var start: String
    var end: String
    var location: String
    var accent: SessionTag
    var initials: String
    /// Day of the month this session belongs to (drives week / month views).
    var dayOfMonth: Int
    /// Minutes since midnight, used to order and lay out the timeline.
    var startMinutes: Int
    /// Absolute start time used for API sync and Apple Calendar export.
    var scheduledAt: Date
    /// Session length in minutes.
    var durationMinutes: Int
    /// Free-form notes shown in the detail card.
    var notes: String
    /// Whether the trainer has checked the client in.
    var isCompleted: Bool
    /// Whether the client missed this session (stays on the calendar, dimmed,
    /// and does not count against their package).
    var isSkipped: Bool

    init(
        id: UUID = UUID(),
        clientID: UUID? = nil,
        clientName: String,
        focus: String,
        start: String,
        end: String,
        location: String,
        accent: SessionTag,
        initials: String,
        dayOfMonth: Int,
        startMinutes: Int,
        scheduledAt: Date? = nil,
        durationMinutes: Int = 60,
        notes: String = "",
        isCompleted: Bool = false,
        isSkipped: Bool = false
    ) {
        self.id = id
        self.clientID = clientID
        self.clientName = clientName
        self.focus = focus
        self.start = start
        self.end = end
        self.location = location
        self.accent = accent
        self.initials = initials
        self.dayOfMonth = dayOfMonth
        self.startMinutes = startMinutes
        self.scheduledAt = scheduledAt ?? Self.scheduledDate(dayOfMonth: dayOfMonth, startMinutes: startMinutes)
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.isCompleted = isCompleted
        self.isSkipped = isSkipped
    }
}

/// Categorical tag that drives the colored tint on a session card.
enum SessionTag: CaseIterable {
    case training
    case strength
    case mobility
    case consult
    case recovery
    case personal

    var label: String {
        switch self {
        case .training: return "Training"
        case .strength: return "Strength"
        case .mobility: return "Mobility"
        case .consult: return "Consult"
        case .recovery: return "Recovery"
        case .personal: return "Personal"
        }
    }

    /// Saturated rail / dot color.
    var tint: Color {
        switch self {
        case .training: return Color(hex: 0x6FB3F2)
        case .strength: return Theme.Color.accent
        case .mobility: return Color(hex: 0x4FC0A8)
        case .consult: return Color(hex: 0x57C77B)
        case .recovery: return Color(hex: 0xC79BF2)
        case .personal: return Color(hex: 0xB6B2A8)
        }
    }

    /// Soft card background tint for the minimalist day blocks.
    var soft: Color {
        switch self {
        case .training: return Color(hex: 0xE4F0FC)
        case .strength: return Color(hex: 0xEEF7D6)
        case .mobility: return Color(hex: 0xDFF3EE)
        case .consult: return Color(hex: 0xE0F4E7)
        case .recovery: return Color(hex: 0xF1E9FB)
        case .personal: return Color(hex: 0xEDE9E0)
        }
    }
}

// MARK: - Time helpers

extension Session {
    /// Converts minutes-since-midnight into a 12-hour clock tuple.
    static func clock(_ minutes: Int) -> (time: String, meridiem: String) {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        let hour24 = wrapped / 60
        let minute = wrapped % 60
        let meridiem = hour24 < 12 ? "AM" : "PM"
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        return (String(format: "%d:%02d", hour12, minute), meridiem)
    }

    /// "2:00 PM" style label for an arbitrary minute value.
    static func display(_ minutes: Int) -> String {
        let c = clock(minutes)
        return "\(c.time) \(c.meridiem)"
    }

    /// Meridiem for this session's start (used by the timeline rows).
    var startMeridiem: String { Session.clock(startMinutes).meridiem }

    /// Full "2:00 PM – 3:00 PM" range string.
    var timeRange: String {
        "\(Session.display(startMinutes)) – \(Session.display(startMinutes + durationMinutes))"
    }

    /// Human title for calendar export, e.g. "Consultation with Sarah".
    var calendarEventTitle: String {
        "\(focus) with \(clientName)"
    }

    /// Local / push reminder title.
    var reminderTitle: String {
        calendarEventTitle
    }

    /// Local / push reminder body.
    var reminderBody: String {
        let time = Session.display(startMinutes)
        if location.isEmpty {
            return "Starts at \(time)"
        }
        return "Starts at \(time) · \(location)"
    }

    /// Trainer → client SMS preview from the session detail card.
    var clientReminderSMS: String {
        let first = clientName.split(separator: " ").first.map(String.init) ?? clientName
        return "Hey \(first), see you for your \(focus.lowercased()) at \(Session.display(startMinutes))!"
    }

    /// Builds a session from editor inputs, deriving display strings.
    static func make(
        id: UUID = UUID(),
        clientID: UUID? = nil,
        clientName: String,
        initials: String,
        dayOfMonth: Int,
        startMinutes: Int,
        scheduledAt: Date? = nil,
        durationMinutes: Int,
        accent: SessionTag,
        location: String,
        notes: String,
        isCompleted: Bool = false,
        isSkipped: Bool = false
    ) -> Session {
        let resolved = scheduledAt ?? Self.scheduledDate(dayOfMonth: dayOfMonth, startMinutes: startMinutes)
        let calendar = Calendar.current
        let resolvedDay = calendar.component(.day, from: resolved)
        let resolvedMinutes = calendar.component(.hour, from: resolved) * 60 + calendar.component(.minute, from: resolved)
        return Session(
            id: id,
            clientID: clientID,
            clientName: clientName,
            focus: accent.label,
            start: clock(resolvedMinutes).time,
            end: display(resolvedMinutes + durationMinutes),
            location: location,
            accent: accent,
            initials: initials,
            dayOfMonth: resolvedDay,
            startMinutes: resolvedMinutes,
            scheduledAt: resolved,
            durationMinutes: durationMinutes,
            notes: notes,
            isCompleted: isCompleted,
            isSkipped: isSkipped
        )
    }

    /// Combines day-of-month and start time in the current month (fallback when no absolute date exists).
    static func scheduledDate(dayOfMonth: Int, startMinutes: Int, monthAnchor: Date = Date()) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: monthAnchor)
        components.day = dayOfMonth
        components.hour = startMinutes / 60
        components.minute = startMinutes % 60
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }
}

extension Session {
    /// The Schedule hub starts empty; the trainer fills it by adding appointments.
    static let sample: [Session] = []

    /// A demo week of sessions for a single client, used by the client
    /// experience. Anchored to the app's June 2026 timeline (today = the 17th):
    /// some sessions are in the past (auto-completed) and some upcoming.
    static func clientDemo(clientName: String, initials: String) -> [Session] {
        func make(day: Int, start: Int, duration: Int, tag: SessionTag, notes: String) -> Session {
            Session.make(
                clientName: clientName,
                initials: initials,
                dayOfMonth: day,
                startMinutes: start,
                durationMinutes: duration,
                accent: tag,
                location: "",
                notes: notes
            )
        }
        return [
            make(day: 10, start: 9 * 60, duration: 60, tag: .strength, notes: "Lower body — squats and posterior chain."),
            make(day: 12, start: 9 * 60, duration: 60, tag: .training, notes: "Conditioning circuit."),
            make(day: 15, start: 9 * 60, duration: 60, tag: .strength, notes: "Upper body push."),
            make(day: 17, start: 14 * 60, duration: 60, tag: .training, notes: "Full-body strength + core finisher."),
            make(day: 19, start: 9 * 60, duration: 60, tag: .mobility, notes: "Mobility and recovery flow."),
            make(day: 20, start: 10 * 60, duration: 60, tag: .strength, notes: "Lower body — deadlift focus."),
            make(day: 24, start: 9 * 60, duration: 60, tag: .training, notes: "Progress check-in session."),
        ]
    }
}
