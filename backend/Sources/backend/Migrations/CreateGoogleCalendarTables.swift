import Fluent

struct CreateGoogleCalendarTables: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(GoogleCalendarToken.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("access_token", .string, .required)
            .field("refresh_token", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("scope", .string, .required)
            .field("verra_calendar_id", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id")
            .create()

        try await database.schema(GoogleCalendarOAuthState.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("state", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime)
            .create()

        try await database.schema(GoogleCalendarExport.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("session_id", .uuid, .required)
            .field("google_event_id", .string, .required)
            .field("calendar_id", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id", "session_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(GoogleCalendarExport.schema).delete()
        try await database.schema(GoogleCalendarOAuthState.schema).delete()
        try await database.schema(GoogleCalendarToken.schema).delete()
    }
}
