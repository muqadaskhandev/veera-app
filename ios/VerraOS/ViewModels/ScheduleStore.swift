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
    var calendarReminderMinutesBefore: Int = 60
    var blockConflictsOnSave: Bool = true
    var useDedicatedVerraCalendar: Bool = true

    /// Month currently visible in the schedule UI (drives calendar import range).
    var visibleMonthAnchor: Date = Date()

    /// Personal calendar blocks imported from Apple Calendar.
    private(set) var busyBlocks: [BusyBlock] = []

    var calendarSyncError: String?
    var isRefreshingCalendar = false

    private static let prefsKey = "verra.schedule.calendarPrefs"
    var onCalendarPrefsPersisted: ((String) -> Void)?

    init(sessions: [Session] = Session.sample, clients: [Client] = Client.roster) {
        self.sessions = sessions
        self.clients = clients
        loadCalendarPrefs()
    }

    /// Sync is considered active when at least one external calendar is linked.
    var isSynced: Bool { googleLinked || appleLinked }

    /// The current day of the month in the user's local calendar.
    var today: Int {
        Calendar.current.component(.day, from: Date())
    }

    /// Current minutes-since-midnight in the user's local time zone.
    var nowMinutes: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    /// Whether a session's time slot has fully elapsed relative to "now".
    func hasPassed(_ session: Session) -> Bool {
        session.scheduledAt.addingTimeInterval(TimeInterval(session.durationMinutes * 60)) <= Date()
    }

    /// Sessions on a given calendar day, ordered by start time.
    func sessions(on date: Date) -> [Session] {
        ScheduleCalendar.sessions(sessions, on: date)
    }

    /// Sessions on a given day within the visible month (legacy day-of-month picker).
    func sessions(on day: Int) -> [Session] {
        guard let date = ScheduleCalendar.date(in: visibleMonthAnchor, day: day) else { return [] }
        return sessions(on: date)
    }

    /// Imported busy blocks on a given calendar day.
    func busyBlocks(on date: Date) -> [BusyBlock] {
        let calendar = Calendar.current
        return busyBlocks
            .filter { calendar.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Imported busy blocks on a given day within the visible month.
    func busyBlocks(on day: Int) -> [BusyBlock] {
        guard let date = ScheduleCalendar.date(in: visibleMonthAnchor, day: day) else { return [] }
        return busyBlocks(on: date)
    }

    /// Sessions plus imported busy blocks for the day timeline.
    func timelineItems(on date: Date) -> [Session] {
        let coaching = sessions(on: date)
        guard isSynced, importPersonalEvents else { return coaching }
        let busy = busyBlocks(on: date).map { $0.asSession() }
        return (coaching + busy).sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Sessions plus imported busy blocks for a day-of-month within the visible month.
    func timelineItems(on day: Int) -> [Session] {
        guard let date = ScheduleCalendar.date(in: visibleMonthAnchor, day: day) else { return [] }
        return timelineItems(on: date)
    }

    /// Coaching sessions in the week containing `anchor`.
    func sessionsInWeek(containing anchor: Date = Date()) -> [Session] {
        ScheduleCalendar.sessionsInWeek(coachingSessions, containing: anchor)
    }

    /// Trainer coaching sessions only — excludes personal blocks and imported calendar busy time.
    var coachingSessions: [Session] {
        sessions.filter { $0.accent != .personal && $0.notes != CalendarSyncService.importedMarker }
    }

    /// Next upcoming coaching session across the full schedule.
    var nextUpcomingSession: Session? {
        let now = Date()
        return coachingSessions
            .filter { !$0.isCompleted && !$0.isSkipped && $0.scheduledAt > now }
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .first
    }

    /// Week-over-week change in scheduled coaching volume.
    func weeklyVolumeTrend(containing anchor: Date = Date()) -> (isUp: Bool, delta: Int) {
        let calendar = Calendar.current
        let thisWeek = sessionsInWeek(containing: anchor).count
        guard let lastWeekAnchor = calendar.date(byAdding: .weekOfYear, value: -1, to: anchor) else {
            return (thisWeek >= 0, 0)
        }
        let lastWeek = ScheduleCalendar.sessionsInWeek(coachingSessions, containing: lastWeekAnchor).count
        let delta = thisWeek - lastWeek
        return (delta >= 0, abs(delta))
    }

    /// Remaining package sessions for the client matching this session, if any.
    func remainingSessions(for session: Session) -> Int? {
        clients.first { $0.name == session.clientName }?.sessionsRemaining
    }

    // MARK: Calendar sync

    func loadCalendarPrefs() {
        // Preferences are loaded from the server via `loadCalendarPrefsFromServer`.
    }

    func loadCalendarPrefsFromServer(_ json: String?) {
        guard let json, let data = json.data(using: .utf8),
              let prefs = try? JSONDecoder().decode(CalendarPrefs.self, from: data) else { return }
        googleLinked = prefs.googleLinked
        appleLinked = prefs.appleLinked
        importPersonalEvents = prefs.importPersonalEvents
        exportSessions = prefs.exportSessions
        calendarReminderMinutesBefore = prefs.calendarReminderMinutesBefore ?? 60
        blockConflictsOnSave = prefs.blockConflictsOnSave ?? true
        useDedicatedVerraCalendar = prefs.useDedicatedVerraCalendar ?? true
        if appleLinked, !exportSessions {
            exportSessions = true
            saveCalendarPrefs()
        }
        reconcileAppleCalendarPermission()
    }

    /// Keeps stored link state in sync with real EventKit permission.
    func reconcileAppleCalendarPermission() {
        guard appleLinked else { return }
        guard CalendarSyncService.canWriteToCalendar else {
            appleLinked = false
            calendarSyncError = CalendarSyncError.accessDenied.localizedDescription
            saveCalendarPrefs()
            return
        }
    }

    func saveCalendarPrefs() {
        let prefs = CalendarPrefs(
            googleLinked: googleLinked,
            appleLinked: appleLinked,
            importPersonalEvents: importPersonalEvents,
            exportSessions: exportSessions,
            calendarReminderMinutesBefore: calendarReminderMinutesBefore,
            blockConflictsOnSave: blockConflictsOnSave,
            useDedicatedVerraCalendar: useDedicatedVerraCalendar
        )
        if let data = try? JSONEncoder().encode(prefs),
           let json = String(data: data, encoding: .utf8) {
            onCalendarPrefsPersisted?(json)
        }
    }

    func startCalendarMonitoring() {
        reconcileAppleCalendarPermission()
        CalendarChangeMonitor.shared.start { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshCalendarData()
            }
        }
    }

    func stopCalendarMonitoring() {
        CalendarChangeMonitor.shared.stop()
    }

    @MainActor
    func connectAppleCalendar() async -> Bool {
        do {
            try await CalendarSyncService.requestAppleCalendarAccess()
            if useDedicatedVerraCalendar {
                try CalendarSyncService.ensureVerraCalendar()
            }
            appleLinked = true
            exportSessions = true
            calendarSyncError = nil
            saveCalendarPrefs()
            await refreshCalendarData()
            await exportSessionsToExternalCalendars()
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
        calendarSyncError = nil
        saveCalendarPrefs()
        Task { @MainActor in await refreshCalendarData() }
    }

    @MainActor
    func connectGoogleCalendar() async -> Bool {
        guard let token = AuthStore.accessToken else { return false }
        do {
            if let status = try? await VerraAPI.fetchGoogleCalendarStatus(accessToken: token),
               status.configured == false {
                calendarSyncError = GoogleCalendarAuthError.notConfigured.localizedDescription
                return false
            }
            try await GoogleCalendarAuthService.connect(accessToken: token)
            googleLinked = true
            calendarSyncError = nil
            saveCalendarPrefs()
            await refreshCalendarData()
            await exportSessionsToExternalCalendars()
            return true
        } catch {
            googleLinked = false
            calendarSyncError = error.localizedDescription
            saveCalendarPrefs()
            return false
        }
    }

    @MainActor
    func disconnectGoogleCalendar() async {
        if let token = AuthStore.accessToken {
            try? await VerraAPI.disconnectGoogleCalendar(accessToken: token)
        }
        googleLinked = false
        calendarSyncError = nil
        saveCalendarPrefs()
        await refreshCalendarData()
    }

    @MainActor
    func syncGoogleConnectionStatus() async {
        guard let token = AuthStore.accessToken else { return }
        if let status = try? await VerraAPI.fetchGoogleCalendarStatus(accessToken: token) {
            googleLinked = status.connected
            saveCalendarPrefs()
        }
    }

    @MainActor
    func refreshCalendarData(forMonthContaining anchor: Date? = nil) async {
        if let anchor {
            visibleMonthAnchor = anchor
        }

        guard isSynced else {
            busyBlocks = []
            return
        }

        isRefreshingCalendar = true
        defer { isRefreshingCalendar = false }

        var blocks: [BusyBlock] = []

        if importPersonalEvents {
            if appleLinked {
                if CalendarSyncService.hasCalendarAccess {
                    blocks += CalendarSyncService.fetchBusyBlocks(forMonthContaining: visibleMonthAnchor)
                } else {
                    appleLinked = false
                    calendarSyncError = CalendarSyncError.accessDenied.localizedDescription
                    saveCalendarPrefs()
                }
            }

            if googleLinked, let token = AuthStore.accessToken,
               let range = importRange(for: visibleMonthAnchor),
               let dtos = try? await VerraAPI.fetchGoogleBusyBlocks(
                   from: range.start,
                   to: range.end,
                   accessToken: token
               ) {
                blocks += dtos.map {
                    BusyBlock(
                        id: $0.id,
                        title: $0.title,
                        startDate: $0.startDate,
                        durationMinutes: $0.durationMinutes
                    )
                }
            }
        }

        busyBlocks = blocks.sorted { $0.startDate < $1.startDate }
    }

    /// Pushes coaching sessions to linked external calendars. Call after saves — not on every busy-block refresh.
    @MainActor
    func exportSessionsToExternalCalendars() async {
        guard exportSessions, isSynced else { return }
        if appleLinked {
            reconcileAppleCalendarPermission()
            guard appleLinked, CalendarSyncService.canWriteToCalendar else { return }
            let count = CalendarSyncService.exportAllSessions(
                sessions,
                reminderMinutesBefore: calendarReminderMinutesBefore,
                useDedicatedCalendar: useDedicatedVerraCalendar
            )
            if count > 0 {
                calendarSyncError = nil
            } else if !sessions.isEmpty {
                calendarSyncError = "No sessions were exported to Apple Calendar. Check calendar permission and the Verra Sessions calendar."
            }
        }
        if googleLinked, let token = AuthStore.accessToken {
            await exportSessionsToGoogle(accessToken: token)
        }
    }

    private func importRange(for anchor: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart),
              let rangeStart = calendar.date(byAdding: .day, value: -7, to: monthStart),
              let rangeEnd = calendar.date(byAdding: .day, value: 7, to: monthEnd) else {
            return nil
        }
        return (rangeStart, rangeEnd)
    }

    @MainActor
    private func exportSessionsToGoogle(accessToken: String) async {
        let payloads = sessions.map {
            VerraAPI.GoogleCalendarExportAllBody.SessionPayload(
                sessionID: $0.id,
                clientName: $0.clientName,
                focus: $0.focus,
                scheduledAt: $0.scheduledAt,
                durationMinutes: $0.durationMinutes,
                location: $0.location,
                notes: $0.notes,
                isSkipped: $0.isSkipped,
                accent: $0.accent == .personal ? "personal" : "coaching"
            )
        }
        try? await VerraAPI.exportAllSessionsToGoogleCalendar(
            VerraAPI.GoogleCalendarExportAllBody(
                sessions: payloads,
                reminderMinutesBefore: calendarReminderMinutesBefore,
                useDedicatedCalendar: useDedicatedVerraCalendar
            ),
            accessToken: accessToken
        )
    }

    func detectConflicts(
        at scheduledAt: Date,
        durationMinutes: Int,
        excludingSessionID: UUID? = nil
    ) -> [ScheduleConflict] {
        CalendarSyncService.detectConflicts(
            start: scheduledAt,
            durationMinutes: durationMinutes,
            excludingSessionID: excludingSessionID,
            sessions: sessions,
            busyBlocks: isSynced && importPersonalEvents ? busyBlocks : []
        )
    }

    func syncSessionToCalendar(_ session: Session) {
        guard exportSessions, session.accent != .personal else { return }
        if appleLinked {
            reconcileAppleCalendarPermission()
            if appleLinked {
                do {
                    _ = try CalendarSyncService.exportSession(
                        session,
                        reminderMinutesBefore: calendarReminderMinutesBefore,
                        useDedicatedCalendar: useDedicatedVerraCalendar
                    )
                    calendarSyncError = nil
                } catch {
                    calendarSyncError = error.localizedDescription
                }
            }
        }
        if googleLinked, let token = AuthStore.accessToken {
            Task {
                try? await VerraAPI.exportSessionToGoogleCalendar(
                    VerraAPI.GoogleCalendarExportBody(
                        sessionID: session.id,
                        clientName: session.clientName,
                        focus: session.focus,
                        scheduledAt: session.scheduledAt,
                        durationMinutes: session.durationMinutes,
                        location: session.location,
                        notes: session.notes,
                        reminderMinutesBefore: calendarReminderMinutesBefore,
                        useDedicatedCalendar: useDedicatedVerraCalendar
                    ),
                    accessToken: token
                )
            }
        }
    }

    func removeSessionFromCalendar(_ sessionID: UUID) {
        CalendarSyncService.deleteExportedSession(sessionID)
        if googleLinked, let token = AuthStore.accessToken {
            Task {
                try? await VerraAPI.deleteGoogleCalendarExport(sessionID: sessionID, accessToken: token)
            }
        }
        SessionReminderService.cancelReminder(for: sessionID)
    }

    // MARK: Server sync

    @MainActor
    func refreshFromServer() async {
        guard let token = AuthStore.accessToken else { return }
        do {
            let dtos = try await VerraAPI.fetchSessions(accessToken: token)
            sessions = dtos.map(SessionLoader.session(from:))
            await exportSessionsToExternalCalendars()
            await SessionReminderService.rescheduleAll(
                for: sessions,
                minutesBefore: calendarReminderMinutesBefore
            )
        } catch {
            // Keep local schedule when offline.
        }
    }

    private func clientID(for session: Session) -> UUID? {
        clients.first(where: { $0.name == session.clientName })?.id
    }

    private func persistSession(_ session: Session) {
        guard let token = AuthStore.accessToken else { return }
        Task {
            do {
                let clientID = clientID(for: session)
                _ = try await VerraAPI.updateSession(
                    id: session.id,
                    body: SessionLoader.updateBody(from: session, clientID: clientID),
                    accessToken: token
                )
            } catch {
                do {
                    let created = try await VerraAPI.createSession(
                        SessionLoader.createBody(from: session, clientID: clientID(for: session)),
                        accessToken: token
                    )
                    if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                        sessions[index] = SessionLoader.session(from: created)
                    }
                } catch {
                    // Local schedule remains usable offline.
                }
            }
        }
    }

    private func persistDelete(_ sessionID: UUID) {
        guard let token = AuthStore.accessToken else { return }
        Task {
            try? await VerraAPI.deleteSession(id: sessionID, accessToken: token)
        }
    }

    private func persistPatch(_ session: Session, isCancelled: Bool = false) {
        guard let token = AuthStore.accessToken else { return }
        Task {
            try? await VerraAPI.updateSession(
                id: session.id,
                body: SessionLoader.updateBody(from: session, clientID: clientID(for: session), isCancelled: isCancelled),
                accessToken: token
            )
        }
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
        persistPatch(sessions[index])
    }

    /// Removes a cancelled session from the timeline.
    func cancel(_ session: Session) {
        removeSessionFromCalendar(session.id)
        persistPatch(session, isCancelled: true)
        persistDelete(session.id)
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
            persistPatch(sessions[index])
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
        removeSessionFromCalendar(session.id)
        persistPatch(sessions[index])
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
        persistPatch(sessions[index])
        syncSessionToCalendar(sessions[index])
        Task {
            try? await SessionReminderService.scheduleReminder(
                for: sessions[index],
                minutesBefore: calendarReminderMinutesBefore
            )
        }
    }

    /// Inserts a new session or replaces an existing one (matched by id).
    func upsert(_ session: Session) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        syncSessionToCalendar(session)
        persistSession(session)
        Task {
            try? await SessionReminderService.scheduleReminder(
                for: session,
                minutesBefore: calendarReminderMinutesBefore
            )
        }
    }
}

private struct CalendarPrefs: Codable {
    var googleLinked: Bool
    var appleLinked: Bool
    var importPersonalEvents: Bool
    var exportSessions: Bool
    var calendarReminderMinutesBefore: Int?
    var blockConflictsOnSave: Bool?
    var useDedicatedVerraCalendar: Bool?
}
