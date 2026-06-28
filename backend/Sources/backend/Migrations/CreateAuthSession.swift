import Fluent

struct CreateAuthSession: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(AuthSession.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("refresh_token_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("revoked_at", .datetime)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(AuthSession.schema).delete()
    }
}
