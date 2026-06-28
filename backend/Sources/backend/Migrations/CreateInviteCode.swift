import Fluent

struct CreateInviteCode: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(InviteCode.schema)
            .id()
            .field("code", .string, .required)
            .field("trainer_id", .uuid, .required, .references(Trainer.schema, "id", onDelete: .cascade))
            .field("created_by_user_id", .uuid, .references(User.schema, "id", onDelete: .setNull))
            .field("redeemed_by_user_id", .uuid, .references(User.schema, "id", onDelete: .setNull))
            .field("client_id", .uuid, .references(Client.schema, "id", onDelete: .setNull))
            .field("expires_at", .datetime)
            .field("redeemed_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "code")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(InviteCode.schema).delete()
    }
}
