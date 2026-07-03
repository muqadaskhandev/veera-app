import Fluent

struct CreateNotificationOutbox: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(NotificationOutbox.schema)
            .id()
            .field("user_id", .uuid, .references(User.schema, "id", onDelete: .setNull))
            .field("channel", .string, .required)
            .field("kind", .string, .required)
            .field("recipient", .string, .required)
            .field("title", .string, .required)
            .field("body", .string, .required)
            .field("status", .string, .required)
            .field("external_id", .string)
            .field("attempt_count", .int, .required)
            .field("max_attempts", .int, .required)
            .field("next_retry_at", .datetime)
            .field("last_error", .string)
            .field("metadata_json", .string)
            .field("scheduled_reminder_id", .uuid)
            .field("sent_at", .datetime)
            .field("delivered_at", .datetime)
            .field("failed_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.schema(PushDeviceToken.schema)
            .field("invalidated_at", .datetime)
            .field("last_error", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PushDeviceToken.schema)
            .deleteField("invalidated_at")
            .deleteField("last_error")
            .update()
        try await database.schema(NotificationOutbox.schema).delete()
    }
}
