import Fluent

struct CreateOuraToken: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(OuraToken.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("access_token", .string, .required)
            .field("refresh_token", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("scope", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(OuraToken.schema).delete()
    }
}
