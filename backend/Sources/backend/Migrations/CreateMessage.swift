import Fluent

struct CreateMessage: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Message.schema)
            .id()
            .field("conversation_id", .uuid, .required, .references(Conversation.schema, "id", onDelete: .cascade))
            .field("kind", .string, .required)
            .field("body", .string, .required)
            .field("is_outgoing", .bool, .required)
            .field("reaction", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Message.schema).delete()
    }
}
