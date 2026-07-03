import Fluent
import Foundation
import Vapor

enum GoogleCalendarService {
    private static let authorizeURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenURL = "https://oauth2.googleapis.com/token"
    private static let calendarAPI = "https://www.googleapis.com/calendar/v3"
    private static let scopes = "https://www.googleapis.com/auth/calendar"
    private static let verraCalendarTitle = "Verra Sessions"
    private static let sessionMarkerPrefix = "verra-session:"

    private struct TokenForm: Content {
        let grant_type: String
        let code: String?
        let refresh_token: String?
        let redirect_uri: String?
        let client_id: String
        let client_secret: String
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
        let scope: String?
    }

    private struct EventsListResponse: Decodable {
        let items: [GoogleAPIEvent]?
    }

    private struct GoogleAPIEvent: Decodable {
        struct EventDateTime: Decodable {
            let dateTime: String?
            let date: String?
        }

        struct ExtendedProperties: Decodable {
            let `private`: [String: String]?
        }

        let id: String?
        let summary: String?
        let description: String?
        let start: EventDateTime?
        let end: EventDateTime?
        let extendedProperties: ExtendedProperties?
    }

    private struct CreatedEvent: Decodable {
        let id: String?
    }

    private struct CalendarListResponse: Decodable {
        struct CalendarEntry: Decodable {
            let id: String?
            let summary: String?
        }

        let items: [CalendarEntry]?
    }

    private struct CreateCalendarBody: Content {
        let summary: String
        let timeZone: String
    }

    private struct CreateEventBody: Content {
        struct EventDateTime: Content {
            let dateTime: String
            let timeZone: String
        }

        struct Reminders: Content {
            struct Override: Content {
                let method: String
                let minutes: Int
            }

            let useDefault: Bool
            let overrides: [Override]
        }

        struct ExtendedProperties: Content {
            let `private`: [String: String]
        }

        let summary: String
        let description: String
        let location: String?
        let start: EventDateTime
        let end: EventDateTime
        let reminders: Reminders
        let extendedProperties: ExtendedProperties
    }

    static func isConfigured() -> Bool {
        guard let clientID = Environment.get("GOOGLE_CLIENT_ID"),
              let clientSecret = Environment.get("GOOGLE_CLIENT_SECRET"),
              !clientID.isEmpty, !clientSecret.isEmpty else {
            return false
        }
        return true
    }

    static func googleRedirectURI(on app: Application) -> String {
        if let configured = Environment.get("GOOGLE_CALENDAR_REDIRECT_URI"), !configured.isEmpty {
            return configured
        }
        let base = Environment.get("APP_URL") ?? "http://127.0.0.1:8080"
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return "\(trimmed)/api/calendar/google/oauth/callback"
    }

    /// Deep link ASWebAuthenticationSession listens for after the server bridge redirect.
    static func appCallbackURI(on app: Application) -> String {
        Environment.get("GOOGLE_CALENDAR_APP_CALLBACK_URI")
            ?? "app.rork.hiyjy25oz4yjrbssyotkw://google-calendar/callback"
    }

    static func redirectURI(on app: Application) -> String {
        googleRedirectURI(on: app)
    }

    static func status(for user: User, on database: any Database, app: Application) async throws -> GoogleCalendarStatusResponse {
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }
        let connected = try await GoogleCalendarToken.query(on: database)
            .filter(\.$user.$id == userID)
            .first() != nil
        return GoogleCalendarStatusResponse(connected: connected, configured: isConfigured())
    }

    static func beginAuthorization(for user: User, on database: any Database, app: Application) async throws -> GoogleCalendarAuthorizeResponse {
        guard isConfigured() else {
            throw Abort(.serviceUnavailable, reason: "Google Calendar is not configured on the server")
        }
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }

        let state = UUID().uuidString
        let expiresAt = Date().addingTimeInterval(600)
        try await GoogleCalendarOAuthState.query(on: database)
            .filter(\.$user.$id == userID)
            .delete()
        try await GoogleCalendarOAuthState(userID: userID, state: state, expiresAt: expiresAt).save(on: database)

        let redirectURI = googleRedirectURI(on: app)
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Environment.get("GOOGLE_CLIENT_ID")),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
        ]

        guard let url = components.url?.absoluteString else {
            throw Abort(.internalServerError, reason: "Failed to build Google authorization URL")
        }

        return GoogleCalendarAuthorizeResponse(
            authorizationURL: url,
            state: state,
            redirectURI: appCallbackURI(on: app)
        )
    }

    static func completeAuthorization(
        for user: User,
        code: String,
        state: String,
        on database: any Database,
        app: Application
    ) async throws -> GoogleCalendarStatusResponse {
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }

        guard let oauthState = try await GoogleCalendarOAuthState.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$state == state)
            .first(),
            oauthState.expiresAt > Date() else {
            throw Abort(.badRequest, reason: "Invalid or expired Google authorization state")
        }

        try await oauthState.delete(on: database)

        let redirectURI = googleRedirectURI(on: app)
        let tokenResponse = try await exchangeCode(code: code, redirectURI: redirectURI, on: app)
        try await saveToken(tokenResponse, for: userID, on: database)
        return GoogleCalendarStatusResponse(connected: true, configured: true)
    }

    static func disconnect(for user: User, on database: any Database) async throws -> HTTPStatus {
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }
        try await GoogleCalendarExport.query(on: database).filter(\.$user.$id == userID).delete()
        try await GoogleCalendarOAuthState.query(on: database).filter(\.$user.$id == userID).delete()
        try await GoogleCalendarToken.query(on: database).filter(\.$user.$id == userID).delete()
        return .noContent
    }

    static func fetchBusyBlocks(
        for user: User,
        from start: Date,
        to end: Date,
        on database: any Database,
        app: Application
    ) async throws -> [BusyBlockDTO] {
        let accessToken = try await validAccessToken(for: user, on: database, app: app)
        let timeMin = iso8601String(start)
        let timeMax = iso8601String(end)

        var components = URLComponents(string: "\(calendarAPI)/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
        ]

        let response = try await app.client.get(URI(string: components.url!.absoluteString)) { req in
            req.headers.bearerAuthorization = .init(token: accessToken)
        }

        guard response.status == .ok else {
            let body = response.body.map { String(buffer: $0) } ?? ""
            app.logger.error("Google Calendar list failed: \(response.status) \(body)")
            throw Abort(.badGateway, reason: "Failed to fetch Google Calendar events")
        }

        let decoded = try response.content.decode(EventsListResponse.self)
        return (decoded.items ?? [])
            .compactMap { event -> BusyBlockDTO? in
                guard !isVerraExported(event) else { return nil }
                guard let startDate = parseEventDate(event.start), let endDate = parseEventDate(event.end) else {
                    return nil
                }
                let duration = max(15, Int(endDate.timeIntervalSince(startDate) / 60))
                let title = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
                return BusyBlockDTO(
                    id: "google-\(event.id ?? UUID().uuidString)",
                    title: title?.isEmpty == false ? title! : "Busy",
                    startDate: startDate,
                    durationMinutes: duration
                )
            }
    }

    static func exportSession(
        for user: User,
        payload: GoogleCalendarExportRequest,
        on database: any Database,
        app: Application
    ) async throws {
        let accessToken = try await validAccessToken(for: user, on: database, app: app)
        guard let userID = user.id else { return }

        let stored = try await GoogleCalendarToken.query(on: database)
            .filter(\.$user.$id == userID)
            .first()
        let useDedicated = payload.useDedicatedCalendar ?? true
        let calendarID = try await resolveExportCalendarID(
            stored: stored,
            useDedicated: useDedicated,
            accessToken: accessToken,
            userID: userID,
            on: database,
            app: app
        )

        let reminderMinutes = payload.reminderMinutesBefore ?? 60
        let endDate = payload.scheduledAt.addingTimeInterval(TimeInterval(payload.durationMinutes * 60))
        let timeZone = TimeZone.current.identifier
        let body = CreateEventBody(
            summary: "\(payload.focus) with \(payload.clientName)",
            description: "\(sessionMarkerPrefix)\(payload.sessionID.uuidString)\n\(payload.notes ?? "")",
            location: payload.location,
            start: .init(dateTime: iso8601String(payload.scheduledAt), timeZone: timeZone),
            end: .init(dateTime: iso8601String(endDate), timeZone: timeZone),
            reminders: .init(useDefault: false, overrides: [.init(method: "popup", minutes: reminderMinutes)]),
            extendedProperties: .init(private: ["verra_session_id": payload.sessionID.uuidString])
        )

        if let existing = try await GoogleCalendarExport.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$sessionID == payload.sessionID)
            .first() {
            let updateURI = eventURI(calendarID: existing.calendarID, eventID: existing.googleEventID)
            let response = try await app.client.put(updateURI) { req in
                req.headers.bearerAuthorization = .init(token: accessToken)
                req.headers.contentType = .json
                try req.content.encode(body)
            }
            if (200..<300).contains(response.status.code) {
                if existing.calendarID != calendarID {
                    existing.calendarID = calendarID
                }
                try await existing.save(on: database)
                return
            }

            let responseBody = response.body.map { String(buffer: $0) } ?? ""
            app.logger.warning(
                "Google Calendar update failed (\(response.status)) for session \(payload.sessionID): \(responseBody). Recreating event."
            )
            _ = try? await app.client.delete(updateURI) { req in
                req.headers.bearerAuthorization = .init(token: accessToken)
            }
            try await existing.delete(on: database)
        }

        let createURI = calendarEventsURI(calendarID: calendarID)
        let response = try await app.client.post(createURI) { req in
            req.headers.bearerAuthorization = .init(token: accessToken)
            req.headers.contentType = .json
            try req.content.encode(body)
        }

        guard response.status == .ok else {
            let responseBody = response.body.map { String(buffer: $0) } ?? ""
            app.logger.error("Google Calendar export failed: \(response.status) \(responseBody)")
            throw Abort(.badGateway, reason: "Failed to export session to Google Calendar")
        }

        let created = try response.content.decode(CreatedEvent.self)
        guard let eventID = created.id else {
            throw Abort(.badGateway, reason: "Google Calendar did not return an event id")
        }

        let export = GoogleCalendarExport(
            userID: userID,
            sessionID: payload.sessionID,
            googleEventID: eventID,
            calendarID: calendarID
        )
        try await export.save(on: database)
    }

    static func exportAllSessions(
        for user: User,
        payload: GoogleCalendarExportAllRequest,
        on database: any Database,
        app: Application
    ) async throws {
        for session in payload.sessions {
            guard session.accent != "personal", !session.isSkipped else { continue }
            do {
                try await exportSession(
                    for: user,
                    payload: GoogleCalendarExportRequest(
                        sessionID: session.sessionID,
                        clientName: session.clientName,
                        focus: session.focus,
                        scheduledAt: session.scheduledAt,
                        durationMinutes: session.durationMinutes,
                        location: session.location,
                        notes: session.notes,
                        reminderMinutesBefore: payload.reminderMinutesBefore,
                        useDedicatedCalendar: payload.useDedicatedCalendar
                    ),
                    on: database,
                    app: app
                )
            } catch {
                app.logger.warning("Google Calendar export failed for session \(session.sessionID): \(error)")
            }
        }
    }

    static func deleteExportedSession(
        for user: User,
        sessionID: UUID,
        on database: any Database,
        app: Application
    ) async throws {
        guard let userID = user.id else { return }
        guard let export = try await GoogleCalendarExport.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$sessionID == sessionID)
            .first() else {
            return
        }

        let accessToken = try await validAccessToken(for: user, on: database, app: app)
        let uri = eventURI(calendarID: export.calendarID, eventID: export.googleEventID)
        _ = try await app.client.delete(uri) { req in
            req.headers.bearerAuthorization = .init(token: accessToken)
        }
        try await export.delete(on: database)
    }

    // MARK: - Token handling

    private static func exchangeCode(code: String, redirectURI: String, on app: Application) async throws -> TokenResponse {
        guard let clientID = Environment.get("GOOGLE_CLIENT_ID"),
              let clientSecret = Environment.get("GOOGLE_CLIENT_SECRET") else {
            throw Abort(.internalServerError, reason: "Google OAuth is not configured")
        }

        let response = try await app.client.post(URI(string: tokenURL)) { req in
            req.headers.contentType = .urlEncodedForm
            try req.content.encode(TokenForm(
                grant_type: "authorization_code",
                code: code,
                refresh_token: nil,
                redirect_uri: redirectURI,
                client_id: clientID,
                client_secret: clientSecret
            ))
        }

        guard response.status == .ok else {
            let body = response.body.map { String(buffer: $0) } ?? ""
            app.logger.error("Google token exchange failed: \(response.status) \(body)")
            throw Abort(.unauthorized, reason: "Google token exchange failed")
        }

        return try response.content.decode(TokenResponse.self)
    }

    private static func refreshAccessToken(refreshToken: String, on app: Application) async throws -> TokenResponse {
        guard let clientID = Environment.get("GOOGLE_CLIENT_ID"),
              let clientSecret = Environment.get("GOOGLE_CLIENT_SECRET") else {
            throw Abort(.internalServerError, reason: "Google OAuth is not configured")
        }

        let response = try await app.client.post(URI(string: tokenURL)) { req in
            req.headers.contentType = .urlEncodedForm
            try req.content.encode(TokenForm(
                grant_type: "refresh_token",
                code: nil,
                refresh_token: refreshToken,
                redirect_uri: nil,
                client_id: clientID,
                client_secret: clientSecret
            ))
        }

        guard response.status == .ok else {
            throw Abort(.unauthorized, reason: "Google token refresh failed")
        }

        return try response.content.decode(TokenResponse.self)
    }

    private static func saveToken(_ response: TokenResponse, for userID: UUID, on database: any Database) async throws {
        let expiresAt = Date().addingTimeInterval(TimeInterval(response.expires_in ?? 3600))
        let refreshToken = response.refresh_token

        if let existing = try await GoogleCalendarToken.query(on: database)
            .filter(\.$user.$id == userID)
            .first() {
            existing.accessToken = response.access_token
            if let refreshToken, !refreshToken.isEmpty {
                existing.refreshToken = refreshToken
            }
            existing.expiresAt = expiresAt
            existing.scope = response.scope ?? scopes
            try await existing.save(on: database)
            return
        }

        guard let refreshToken, !refreshToken.isEmpty else {
            throw Abort(.badRequest, reason: "Google did not return a refresh token. Try disconnecting and connecting again.")
        }

        let token = GoogleCalendarToken(
            userID: userID,
            accessToken: response.access_token,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scope: response.scope ?? scopes
        )
        try await token.save(on: database)
    }

    private static func validAccessToken(
        for user: User,
        on database: any Database,
        app: Application
    ) async throws -> String {
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }
        guard let stored = try await GoogleCalendarToken.query(on: database)
            .filter(\.$user.$id == userID)
            .first() else {
            throw Abort(.badRequest, reason: "Google Calendar is not connected")
        }

        if stored.expiresAt > Date().addingTimeInterval(60) {
            return stored.accessToken
        }

        let refreshed = try await refreshAccessToken(refreshToken: stored.refreshToken, on: app)
        stored.accessToken = refreshed.access_token
        stored.expiresAt = Date().addingTimeInterval(TimeInterval(refreshed.expires_in ?? 3600))
        if let newRefresh = refreshed.refresh_token, !newRefresh.isEmpty {
            stored.refreshToken = newRefresh
        }
        try await stored.save(on: database)
        return stored.accessToken
    }

    private static func resolveExportCalendarID(
        stored: GoogleCalendarToken?,
        useDedicated: Bool,
        accessToken: String,
        userID: UUID,
        on database: any Database,
        app: Application
    ) async throws -> String {
        if useDedicated {
            if let existing = stored?.verraCalendarID, !existing.isEmpty {
                return existing
            }
            let createdID = try await ensureVerraCalendar(accessToken: accessToken, on: app)
            if let stored {
                stored.verraCalendarID = createdID
                try await stored.save(on: database)
            }
            return createdID
        }
        return "primary"
    }

    private static func ensureVerraCalendar(accessToken: String, on app: Application) async throws -> String {
        let listResponse = try await app.client.get(URI(string: "\(calendarAPI)/users/me/calendarList")) { req in
            req.headers.bearerAuthorization = .init(token: accessToken)
        }
        if listResponse.status == .ok,
           let list = try? listResponse.content.decode(CalendarListResponse.self),
           let existing = list.items?.first(where: { $0.summary == verraCalendarTitle }),
           let id = existing.id {
            return id
        }

        let createResponse = try await app.client.post(URI(string: "\(calendarAPI)/calendars")) { req in
            req.headers.bearerAuthorization = .init(token: accessToken)
            req.headers.contentType = .json
            try req.content.encode(CreateCalendarBody(summary: verraCalendarTitle, timeZone: TimeZone.current.identifier))
        }

        guard createResponse.status == .ok else {
            throw Abort(.badGateway, reason: "Failed to create Verra Sessions calendar in Google")
        }

        struct CreatedCalendar: Decodable { let id: String? }
        let created = try createResponse.content.decode(CreatedCalendar.self)
        guard let id = created.id else {
            throw Abort(.badGateway, reason: "Google did not return a calendar id")
        }
        return id
    }

    // MARK: - Helpers

    private static func encodePathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func calendarEventsURI(calendarID: String) -> URI {
        URI(string: "\(calendarAPI)/calendars/\(encodePathComponent(calendarID))/events")
    }

    private static func eventURI(calendarID: String, eventID: String) -> URI {
        URI(string: "\(calendarAPI)/calendars/\(encodePathComponent(calendarID))/events/\(encodePathComponent(eventID))")
    }

    private static func isVerraExported(_ event: GoogleAPIEvent) -> Bool {
        if let sessionID = event.extendedProperties?.private?["verra_session_id"], !sessionID.isEmpty {
            return true
        }
        if let description = event.description, description.contains(sessionMarkerPrefix) {
            return true
        }
        if let summary = event.summary, summary.hasPrefix("Verra ·") {
            return true
        }
        if let summary = event.summary {
            let exportedPrefixes = [
                "Training with ", "Consultation with ", "Strength with ",
                "Mobility with ", "Recovery with ",
            ]
            if exportedPrefixes.contains(where: { summary.hasPrefix($0) }) {
                return true
            }
        }
        return false
    }

    private static func parseEventDate(_ value: GoogleAPIEvent.EventDateTime?) -> Date? {
        guard let value else { return nil }
        if let dateTime = value.dateTime {
            return iso8601Date(from: dateTime)
        }
        if let date = value.date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: date)
        }
        return nil
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func iso8601Date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
