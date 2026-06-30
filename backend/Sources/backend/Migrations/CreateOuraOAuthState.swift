import Fluent

struct CreateOuraOAuthState: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(OuraOAuthState.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("state", .string, .required)
            .field("expires_at", .datetime, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(OuraOAuthState.schema).delete()
    }
}
