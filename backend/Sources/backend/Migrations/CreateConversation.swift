import Fluent

struct CreateConversation: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Conversation.schema)
            .id()
            .field("trainer_id", .uuid, .required, .references(Trainer.schema, "id", onDelete: .cascade))
            .field("client_id", .uuid, .required, .references(Client.schema, "id", onDelete: .cascade))
            .field("client_name", .string, .required)
            .field("initials", .string, .required)
            .field("is_unread", .bool, .required)
            .field("last_active_at", .datetime, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Conversation.schema).delete()
    }
}
