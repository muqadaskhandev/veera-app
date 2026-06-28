import Fluent

struct CreateSession: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Session.schema)
            .id()
            .field("trainer_id", .uuid, .required, .references(Trainer.schema, "id", onDelete: .cascade))
            .field("client_id", .uuid, .references(Client.schema, "id", onDelete: .setNull))
            .field("client_name", .string, .required)
            .field("focus", .string, .required)
            .field("location", .string, .required)
            .field("accent", .string, .required)
            .field("initials", .string, .required)
            .field("scheduled_at", .datetime, .required)
            .field("duration_minutes", .int, .required)
            .field("notes", .string, .required)
            .field("is_completed", .bool, .required)
            .field("is_skipped", .bool, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Session.schema).delete()
    }
}
