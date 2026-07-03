import EventKit
import Foundation
import OSLog
import UIKit

/// A personal calendar block imported from Apple Calendar.
struct BusyBlock: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let durationMinutes: Int

    var dayOfMonth: Int {
        Calendar.current.component(.day, from: startDate)
    }

    var startMinutes: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: startDate)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    func asSession() -> Session {
        Session.make(
            id: CalendarSyncService.stableUUID(for: id),
            clientName: title.isEmpty ? "Busy" : title,
            initials: "•",
            dayOfMonth: dayOfMonth,
            startMinutes: startMinutes,
            scheduledAt: startDate,
            durationMinutes: durationMinutes,
            accent: .personal,
            location: "",
            notes: CalendarSyncService.importedMarker
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
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was denied. Enable it in Settings → Verra → Calendars."
        case .unavailable:
            return "Calendar is not available on this device."
        case .exportFailed:
            return "Could not save the session to Apple Calendar."
        }
    }
}

/// Reads and writes Apple Calendar via EventKit (local only — no backend API).
enum CalendarSyncService {
    static let importedMarker = "Imported from Apple Calendar"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VerraOS", category: "CalendarSync")

    private static let store = EKEventStore()
    private static let exportedEventKey = "verra.calendar.exportedEvents"
    private static let verraCalendarTitle = "Verra Sessions"
    private static let verraMarkerPrefix = "verra-session:"

    // MARK: - Access

    static func requestAppleCalendarAccess() async throws {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw CalendarSyncError.accessDenied }
    }

    static var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    static var hasCalendarAccess: Bool {
        authorizationStatus == .fullAccess
    }

    /// Enough permission to create/update calendar events (full or write-only).
    static var canWriteToCalendar: Bool {
        switch authorizationStatus {
        case .fullAccess, .writeOnly: return true
        default: return false
        }
    }

    static func openSettingsURL() -> URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    // MARK: - Import

    static func fetchBusyBlocks(from start: Date, to end: Date) -> [BusyBlock] {
        guard isAuthorized else { return [] }

        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: start)
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) else {
            return []
        }

        let predicate = store.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: nil)
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
                    startDate: event.startDate,
                    durationMinutes: duration
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    static func fetchBusyBlocks(forMonthContaining anchor: Date) -> [BusyBlock] {
        guard isAuthorized else { return [] }

        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart),
              let rangeStart = calendar.date(byAdding: .day, value: -7, to: monthStart),
              let rangeEnd = calendar.date(byAdding: .day, value: 7, to: monthEnd) else {
            return []
        }
        return fetchBusyBlocks(from: rangeStart, to: rangeEnd)
    }

    // MARK: - Export

    @discardableResult
    static func exportSession(_ session: Session, reminderMinutesBefore: Int = 60, useDedicatedCalendar: Bool = true) throws -> String? {
        guard canExport else {
            logger.warning("Apple Calendar export skipped — permission status: \(String(describing: authorizationStatus.rawValue))")
            throw CalendarSyncError.accessDenied
        }

        if useDedicatedCalendar {
            try ensureVerraCalendar()
        }

        let start = session.scheduledAt
        let end = start.addingTimeInterval(TimeInterval(session.durationMinutes * 60))

        let event: EKEvent
        if let existingID = exportedEventMap()[session.id.uuidString],
           let existing = store.event(withIdentifier: existingID) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = try exportCalendar(useDedicated: useDedicatedCalendar)
        }

        event.title = session.calendarEventTitle
        event.startDate = start
        event.endDate = end
        event.location = session.location
        event.notes = "\(verraMarkerPrefix)\(session.id.uuidString)\n\(session.notes)"
        event.alarms = [EKAlarm(relativeOffset: TimeInterval(-reminderMinutesBefore * 60))]

        try store.save(event, span: .thisEvent, commit: true)

        if let identifier = event.eventIdentifier {
            saveExportedEvent(sessionID: session.id, eventIdentifier: identifier)
            logger.info("Apple Calendar exported \"\(session.calendarEventTitle, privacy: .public)\" to \(event.calendar?.title ?? "calendar", privacy: .public)")
            return identifier
        }
        logger.error("Apple Calendar save succeeded but event has no identifier")
        return nil
    }

    @discardableResult
    static func exportAllSessions(_ sessions: [Session], reminderMinutesBefore: Int, useDedicatedCalendar: Bool) -> Int {
        guard canExport else {
            logger.warning("Apple Calendar bulk export skipped — no write permission")
            return 0
        }
        var exported = 0
        for session in sessions where session.accent != .personal && !session.isSkipped {
            do {
                if try exportSession(
                    session,
                    reminderMinutesBefore: reminderMinutesBefore,
                    useDedicatedCalendar: useDedicatedCalendar
                ) != nil {
                    exported += 1
                }
            } catch {
                logger.error("Apple Calendar export failed for \(session.id.uuidString): \(error.localizedDescription, privacy: .public)")
            }
        }
        logger.info("Apple Calendar bulk export finished — \(exported) of \(sessions.count) sessions")
        return exported
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
        start: Date,
        durationMinutes: Int,
        excludingSessionID: UUID?,
        sessions: [Session],
        busyBlocks: [BusyBlock]
    ) -> [ScheduleConflict] {
        let calendar = Calendar.current
        var results: [ScheduleConflict] = []

        for session in sessions {
            guard session.id != excludingSessionID else { continue }
            guard session.accent != .personal, !session.isSkipped else { continue }
            guard calendar.isDate(session.scheduledAt, inSameDayAs: start) else { continue }
            if rangesOverlap(
                minutesSinceMidnight(start, calendar: calendar),
                durationMinutes,
                minutesSinceMidnight(session.scheduledAt, calendar: calendar),
                session.durationMinutes
            ) {
                results.append(ScheduleConflict(
                    title: session.clientName,
                    timeRange: session.timeRange,
                    kind: .session
                ))
            }
        }

        for block in busyBlocks {
            guard calendar.isDate(block.startDate, inSameDayAs: start) else { continue }
            if rangesOverlap(
                minutesSinceMidnight(start, calendar: calendar),
                durationMinutes,
                block.startMinutes,
                block.durationMinutes
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

    private static var isAuthorized: Bool { hasCalendarAccess }

    private static var canExport: Bool { canWriteToCalendar }

    private static func exportCalendar(useDedicated: Bool) throws -> EKCalendar {
        if useDedicated, let calendar = findVerraCalendar() {
            return calendar
        }
        if let defaultCalendar = store.defaultCalendarForNewEvents {
            return defaultCalendar
        }
        throw CalendarSyncError.exportFailed
    }

    private static func findVerraCalendar() -> EKCalendar? {
        store.calendars(for: .event).first { $0.title == verraCalendarTitle }
    }

    @discardableResult
    static func ensureVerraCalendar() throws -> EKCalendar {
        if let existing = findVerraCalendar() {
            return existing
        }
        guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first else {
            throw CalendarSyncError.exportFailed
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = verraCalendarTitle
        calendar.source = source
        calendar.cgColor = CGColor(red: 0.76, green: 0.95, blue: 0.24, alpha: 1)
        try store.saveCalendar(calendar, commit: true)
        return calendar
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

/// Observes Apple Calendar changes and notifies the schedule store to refresh.
final class CalendarChangeMonitor {
    static let shared = CalendarChangeMonitor()

    private var observer: NSObjectProtocol?

    func start(onChange: @escaping () -> Void) {
        stop()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { _ in
            onChange()
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}
