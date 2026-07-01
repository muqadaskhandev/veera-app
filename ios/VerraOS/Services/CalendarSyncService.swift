import EventKit
import Foundation

/// A personal calendar block imported from Apple Calendar.
struct BusyBlock: Identifiable, Hashable {
    let id: String
    let title: String
    let dayOfMonth: Int
    let startMinutes: Int
    let durationMinutes: Int

    func asSession() -> Session {
        Session.make(
            id: CalendarSyncService.stableUUID(for: id),
            clientName: title.isEmpty ? "Busy" : title,
            initials: "•",
            dayOfMonth: dayOfMonth,
            startMinutes: startMinutes,
            durationMinutes: durationMinutes,
            accent: .personal,
            location: "",
            notes: "Imported from Apple Calendar"
        )
    }
}

struct ScheduleConflict: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case session
        case busyBlock
    }

    let id = UUID()
    let title: String
    let timeRange: String
    let kind: Kind
}

enum CalendarSyncError: LocalizedError {
    case accessDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Calendar access was denied. Enable it in Settings → Verra → Calendars."
        case .unavailable: return "Calendar is not available on this device."
        }
    }
}

/// Reads and writes Apple Calendar via EventKit.
enum CalendarSyncService {
    private static let store = EKEventStore()
    private static let exportedEventKey = "verra.calendar.exportedEvents"
    private static let verraMarkerPrefix = "verra-session:"

    // MARK: - Access

    static func requestAppleCalendarAccess() async throws {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw CalendarSyncError.accessDenied }
    }

    static var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Import

    static func fetchBusyBlocks(for dayOfMonth: Int, in monthAnchor: Date = Date()) -> [BusyBlock] {
        guard isAuthorized else { return [] }

        let calendar = Calendar.current
        guard let dayDate = calendar.date(
            from: DateComponents(
                year: calendar.component(.year, from: monthAnchor),
                month: calendar.component(.month, from: monthAnchor),
                day: dayOfMonth
            )
        ) else { return [] }

        let start = calendar.startOfDay(for: dayDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let exported = exportedEventMap()

        return store.events(matching: predicate)
            .filter { event in
                guard let identifier = event.eventIdentifier else { return true }
                return !exported.values.contains(identifier)
            }
            .compactMap { event -> BusyBlock? in
                guard !event.isAllDay else { return nil }
                let startMinutes = minutesSinceMidnight(event.startDate, calendar: calendar)
                let endMinutes = minutesSinceMidnight(event.endDate, calendar: calendar)
                let duration = max(15, endMinutes - startMinutes)
                return BusyBlock(
                    id: "busy-\(event.eventIdentifier ?? UUID().uuidString)",
                    title: event.title ?? "Busy",
                    dayOfMonth: dayOfMonth,
                    startMinutes: startMinutes,
                    durationMinutes: duration
                )
            }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    static func fetchBusyBlocks(forMonthContaining anchor: Date = Date()) -> [BusyBlock] {
        guard isAuthorized else { return [] }

        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: anchor) else { return [] }
        return range.flatMap { fetchBusyBlocks(for: $0, in: anchor) }
    }

    // MARK: - Export

    @discardableResult
    static func exportSession(_ session: Session, monthAnchor: Date = Date()) throws -> String? {
        guard isAuthorized else { return nil }

        let calendar = Calendar.current
        guard let start = date(for: session, monthAnchor: monthAnchor, calendar: calendar) else {
            return nil
        }
        let end = start.addingTimeInterval(TimeInterval(session.durationMinutes * 60))

        let event: EKEvent
        if let existingID = exportedEventMap()[session.id.uuidString],
           let existing = store.event(withIdentifier: existingID) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = store.defaultCalendarForNewEvents
        }

        event.title = "Verra · \(session.clientName)"
        event.startDate = start
        event.endDate = end
        event.location = session.location
        event.notes = "\(verraMarkerPrefix)\(session.id.uuidString)\n\(session.notes)"
        try store.save(event, span: .thisEvent, commit: true)

        if let identifier = event.eventIdentifier {
            saveExportedEvent(sessionID: session.id, eventIdentifier: identifier)
            return identifier
        }
        return nil
    }

    static func deleteExportedSession(_ sessionID: UUID) {
        guard isAuthorized else { return }
        var map = exportedEventMap()
        guard let eventID = map.removeValue(forKey: sessionID.uuidString),
              let event = store.event(withIdentifier: eventID) else {
            persistExportedEventMap(map)
            return
        }
        try? store.remove(event, span: .thisEvent, commit: true)
        persistExportedEventMap(map)
    }

    // MARK: - Conflicts

    static func detectConflicts(
        dayOfMonth: Int,
        startMinutes: Int,
        durationMinutes: Int,
        excludingSessionID: UUID?,
        sessions: [Session],
        busyBlocks: [BusyBlock]
    ) -> [ScheduleConflict] {
        var results: [ScheduleConflict] = []

        for session in sessions where session.dayOfMonth == dayOfMonth {
            guard session.id != excludingSessionID else { continue }
            guard session.accent != .personal, !session.isSkipped else { continue }
            if rangesOverlap(
                startMinutes, durationMinutes,
                session.startMinutes, session.durationMinutes
            ) {
                results.append(ScheduleConflict(
                    title: session.clientName,
                    timeRange: session.timeRange,
                    kind: .session
                ))
            }
        }

        for block in busyBlocks where block.dayOfMonth == dayOfMonth {
            if rangesOverlap(
                startMinutes, durationMinutes,
                block.startMinutes, block.durationMinutes
            ) {
                results.append(ScheduleConflict(
                    title: block.title,
                    timeRange: "\(Session.display(block.startMinutes)) – \(Session.display(block.startMinutes + block.durationMinutes))",
                    kind: .busyBlock
                ))
            }
        }

        return results
    }

    // MARK: - Helpers

    /// Whether the app can read calendar events (required for import; export needs write or full).
    static var hasCalendarAccess: Bool {
        authorizationStatus == .fullAccess
    }

    private static var isAuthorized: Bool {
        hasCalendarAccess
    }

    private static func rangesOverlap(_ startA: Int, _ durationA: Int, _ startB: Int, _ durationB: Int) -> Bool {
        let endA = startA + durationA
        let endB = startB + durationB
        return startA < endB && startB < endA
    }

    private static func minutesSinceMidnight(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func date(for session: Session, monthAnchor: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month], from: monthAnchor)
        components.day = session.dayOfMonth
        components.hour = session.startMinutes / 60
        components.minute = session.startMinutes % 60
        return calendar.date(from: components)
    }

    private static func exportedEventMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: exportedEventKey) as? [String: String] ?? [:]
    }

    private static func saveExportedEvent(sessionID: UUID, eventIdentifier: String) {
        var map = exportedEventMap()
        map[sessionID.uuidString] = eventIdentifier
        persistExportedEventMap(map)
    }

    private static func persistExportedEventMap(_ map: [String: String]) {
        UserDefaults.standard.set(map, forKey: exportedEventKey)
    }

    /// Deterministic UUID for imported calendar events (stable across refreshes).
    static func stableUUID(for key: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in key.utf8.enumerated() {
            bytes[index % 16] ^= byte
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
