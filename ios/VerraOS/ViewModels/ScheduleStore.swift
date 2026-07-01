//
//  ScheduleStore.swift
//  VerraOS
//

import SwiftUI

/// Owns the mutable schedule data: sessions, the client roster, and calendar
/// sync configuration. Shared via the environment so the detail card, the
/// appointment editor, and the sync settings all read and write the same state.
@Observable
final class ScheduleStore {
    var sessions: [Session]
    var clients: [Client]

    // Calendar sync configuration
    var googleLinked: Bool = false
    var appleLinked: Bool = false
    var importPersonalEvents: Bool = true
    var exportSessions: Bool = false

    /// Personal calendar blocks imported from Apple Calendar.
    private(set) var busyBlocks: [BusyBlock] = []

    var calendarSyncError: String?
    var isRefreshingCalendar = false

    private static let prefsKey = "verra.schedule.calendarPrefs"

    init(sessions: [Session] = Session.sample, clients: [Client] = Client.roster) {
        self.sessions = sessions
        self.clients = clients
        loadCalendarPrefs()
    }

    /// Sync is considered active when at least one external calendar is linked.
    var isSynced: Bool { googleLinked || appleLinked }

    /// The current day of the month within the app's June 2026 timeline. Uses the
    /// real date when it falls inside the demo month, otherwise anchors to the
    /// dashboard's "Wednesday, June 17" reference day.
    var today: Int {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        if comps.year == 2026, comps.month == 6, let day = comps.day { return day }
        return 17
    }

    /// Current minutes-since-midnight within the demo timeline. Uses the real
    /// clock when the date falls inside June 2026, otherwise anchors to midday on
    /// the "Wednesday, June 17" reference day so morning slots read as passed.
    var nowMinutes: Int {
        let comps = Calendar.current.dateComponents([.year, .month, .hour, .minute], from: Date())
        if comps.year == 2026, comps.month == 6 {
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
        return 12 * 60
    }

    /// Whether a session's time slot has fully elapsed relative to "now".
    func hasPassed(_ session: Session) -> Bool {
        if session.dayOfMonth < today { return true }
        if session.dayOfMonth > today { return false }
        return session.startMinutes + session.durationMinutes <= nowMinutes
    }

    /// Sessions on a given day, ordered by start time.
    func sessions(on day: Int) -> [Session] {
        sessions
            .filter { $0.dayOfMonth == day }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Imported busy blocks on a given day.
    func busyBlocks(on day: Int) -> [BusyBlock] {
        busyBlocks
            .filter { $0.dayOfMonth == day }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Sessions plus imported busy blocks for the day timeline.
    func timelineItems(on day: Int) -> [Session] {
        let coaching = sessions(on: day)
        guard appleLinked, importPersonalEvents else { return coaching }
        let busy = busyBlocks(on: day).map { $0.asSession() }
        return (coaching + busy).sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Remaining package sessions for the client matching this session, if any.
    func remainingSessions(for session: Session) -> Int? {
        clients.first { $0.name == session.clientName }?.sessionsRemaining
    }

    // MARK: Calendar sync

    func loadCalendarPrefs() {
        guard let data = UserDefaults.standard.data(forKey: Self.prefsKey),
              let prefs = try? JSONDecoder().decode(CalendarPrefs.self, from: data) else { return }
        googleLinked = prefs.googleLinked
        appleLinked = prefs.appleLinked
        importPersonalEvents = prefs.importPersonalEvents
        exportSessions = prefs.exportSessions
    }

    func saveCalendarPrefs() {
        let prefs = CalendarPrefs(
            googleLinked: googleLinked,
            appleLinked: appleLinked,
            importPersonalEvents: importPersonalEvents,
            exportSessions: exportSessions
        )
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.prefsKey)
        }
    }

    @MainActor
    func connectAppleCalendar() async -> Bool {
        do {
            try await CalendarSyncService.requestAppleCalendarAccess()
            appleLinked = true
            calendarSyncError = nil
            saveCalendarPrefs()
            await refreshCalendarData()
            return true
        } catch {
            appleLinked = false
            calendarSyncError = error.localizedDescription
            saveCalendarPrefs()
            return false
        }
    }

    func disconnectAppleCalendar() {
        appleLinked = false
        busyBlocks = []
        calendarSyncError = nil
        saveCalendarPrefs()
    }

    @MainActor
    func refreshCalendarData() async {
        guard appleLinked else {
            busyBlocks = []
            return
        }

        let status = CalendarSyncService.authorizationStatus
        let hasAccess: Bool
        if #available(iOS 17.0, *) {
            hasAccess = status == .fullAccess || status == .authorized
        } else {
            hasAccess = status == .authorized
        }
        guard hasAccess else {
            appleLinked = false
            busyBlocks = []
            calendarSyncError = CalendarSyncError.accessDenied.localizedDescription
            saveCalendarPrefs()
            return
        }

        isRefreshingCalendar = true
        defer { isRefreshingCalendar = false }

        if importPersonalEvents {
            busyBlocks = CalendarSyncService.fetchBusyBlocks(forMonthContaining: Date())
        } else {
            busyBlocks = []
        }

        if exportSessions {
            for session in sessions where session.accent != .personal {
                try? CalendarSyncService.exportSession(session)
            }
        }
    }

    func detectConflicts(
        dayOfMonth: Int,
        startMinutes: Int,
        durationMinutes: Int,
        excludingSessionID: UUID? = nil
    ) -> [ScheduleConflict] {
        CalendarSyncService.detectConflicts(
            dayOfMonth: dayOfMonth,
            startMinutes: startMinutes,
            durationMinutes: durationMinutes,
            excludingSessionID: excludingSessionID,
            sessions: sessions,
            busyBlocks: appleLinked && importPersonalEvents ? busyBlocks : []
        )
    }

    func syncSessionToCalendar(_ session: Session) {
        guard appleLinked, exportSessions, session.accent != .personal else { return }
        try? CalendarSyncService.exportSession(session)
    }

    func removeSessionFromCalendar(_ sessionID: UUID) {
        CalendarSyncService.deleteExportedSession(sessionID)
        SessionReminderService.cancelReminder(for: sessionID)
    }

    // MARK: Mutations

    /// Marks a session complete and deducts one from the client's balance.
    func checkIn(_ session: Session) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].isCompleted = true
        if let clientIndex = clients.firstIndex(where: { $0.name == session.clientName }) {
            clients[clientIndex].sessionsRemaining = max(0, clients[clientIndex].sessionsRemaining - 1)
        }
        SessionReminderService.cancelReminder(for: session.id)
    }

    /// Removes a cancelled session from the timeline.
    func cancel(_ session: Session) {
        removeSessionFromCalendar(session.id)
        sessions.removeAll { $0.id == session.id }
    }

    /// Marks any session whose time slot has fully passed as completed and
    /// deducts it from the client's balance — in both this store and the shared
    /// client roster — so the "sessions left" count stays accurate automatically.
    func reconcilePastSessions(clientStore: ClientStore) {
        for index in sessions.indices {
            let session = sessions[index]
            guard !session.isCompleted,
                  !session.isSkipped,
                  session.accent != .personal,
                  hasPassed(session) else { continue }
            sessions[index].isCompleted = true
            if let clientIndex = clients.firstIndex(where: { $0.name == session.clientName }) {
                clients[clientIndex].sessionsRemaining = max(0, clients[clientIndex].sessionsRemaining - 1)
            }
            clientStore.deductSession(forName: session.clientName)
            SessionReminderService.cancelReminder(for: session.id)
        }
    }

    /// Marks a session as skipped: it stays on the calendar but no longer counts
    /// against the client's package. If the session had already auto-counted, the
    /// deducted session is refunded back to the client.
    func skip(_ session: Session, clientStore: ClientStore) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        let wasCounted = sessions[index].isCompleted
        sessions[index].isSkipped = true
        sessions[index].isCompleted = false
        SessionReminderService.cancelReminder(for: session.id)
        guard wasCounted, session.accent != .personal else { return }
        if let clientIndex = clients.firstIndex(where: { $0.name == session.clientName }) {
            clients[clientIndex].sessionsRemaining += 1
        }
        clientStore.refundSession(forName: session.clientName)
    }

    /// Restores a skipped session back to scheduled. Reconcile will re-count it on
    /// the next pass if its time has already passed.
    func unskip(_ session: Session) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].isSkipped = false
    }

    /// Inserts a new session or replaces an existing one (matched by id).
    func upsert(_ session: Session) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        syncSessionToCalendar(session)
        Task {
            try? await SessionReminderService.scheduleReminder(for: session)
        }
    }
}

private struct CalendarPrefs: Codable {
    var googleLinked: Bool
    var appleLinked: Bool
    var importPersonalEvents: Bool
    var exportSessions: Bool
}
