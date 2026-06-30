import Fluent

struct CreateWearableConnection: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(WearableConnection.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("provider", .string, .required)
            .field("connected_at", .datetime, .required)
            .field("last_synced_at", .datetime)
            .unique(on: "user_id", "provider")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(WearableConnection.schema).delete()
    }
}
