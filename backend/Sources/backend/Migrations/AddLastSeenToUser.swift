import Fluent

struct AddLastSeenToUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(User.schema)
            .field("last_seen_at", .datetime)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(User.schema)
            .deleteField("last_seen_at")
            .update()
    }
}
