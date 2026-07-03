import Fluent
import Vapor

final class GoogleCalendarToken: Model, @unchecked Sendable {
    static let schema = "google_calendar_tokens"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "access_token")
    var accessToken: String

    @Field(key: "refresh_token")
    var refreshToken: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @Field(key: "scope")
    var scope: String

    @OptionalField(key: "verra_calendar_id")
    var verraCalendarID: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        scope: String,
        verraCalendarID: String? = nil
    ) {
        self.id = id
        self.$user.id = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
        self.verraCalendarID = verraCalendarID
    }
}

final class GoogleCalendarOAuthState: Model, @unchecked Sendable {
    static let schema = "google_calendar_oauth_states"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "state")
    var state: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, userID: UUID, state: String, expiresAt: Date) {
        self.id = id
        self.$user.id = userID
        self.state = state
        self.expiresAt = expiresAt
    }
}

final class GoogleCalendarExport: Model, @unchecked Sendable {
    static let schema = "google_calendar_exports"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "session_id")
    var sessionID: UUID

    @Field(key: "google_event_id")
    var googleEventID: String

    @Field(key: "calendar_id")
    var calendarID: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        sessionID: UUID,
        googleEventID: String,
        calendarID: String
    ) {
        self.id = id
        self.$user.id = userID
        self.sessionID = sessionID
        self.googleEventID = googleEventID
        self.calendarID = calendarID
    }
}

struct GoogleCalendarAuthorizeResponse: Content {
    let authorizationURL: String
    let state: String
    let redirectURI: String
}

struct GoogleCalendarCallbackRequest: Content {
    let code: String
    let state: String
}

struct GoogleCalendarStatusResponse: Content {
    let connected: Bool
    let configured: Bool
}

struct BusyBlockDTO: Content {
    let id: String
    let title: String
    let startDate: Date
    let durationMinutes: Int
}

struct GoogleCalendarExportRequest: Content {
    let sessionID: UUID
    let clientName: String
    let focus: String
    let scheduledAt: Date
    let durationMinutes: Int
    let location: String?
    let notes: String?
    let reminderMinutesBefore: Int?
    let useDedicatedCalendar: Bool?
}

struct GoogleCalendarExportAllRequest: Content {
    struct SessionPayload: Content {
        let sessionID: UUID
        let clientName: String
        let focus: String
        let scheduledAt: Date
        let durationMinutes: Int
        let location: String?
        let notes: String?
        let isSkipped: Bool
        let accent: String
    }

    let sessions: [SessionPayload]
    let reminderMinutesBefore: Int?
    let useDedicatedCalendar: Bool?
}
