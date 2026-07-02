import Fluent

struct CreatePushDeviceToken: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PushDeviceToken.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("token", .string, .required)
            .field("platform", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "token")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PushDeviceToken.schema).delete()
    }
}
