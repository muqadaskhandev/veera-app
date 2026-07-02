import Fluent
import SQLKit

struct EnhanceChatMessaging: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Message.schema)
            .field("sender_user_id", .uuid, .references(User.schema, "id", onDelete: .setNull))
            .field("attachment_url", .string)
            .field("status", .string)
            .update()

        try await database.schema(Conversation.schema)
            .field("client_is_unread", .bool)
            .field("last_message_preview", .string)
            .field("last_message_at", .datetime)
            .unique(on: "trainer_id", "client_id")
            .update()

        if let sql = database as? any SQLDatabase {
            try await sql.raw("""
                UPDATE conversations SET client_is_unread = false WHERE client_is_unread IS NULL
                """).run()
        }
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Message.schema)
            .deleteField("sender_user_id")
            .deleteField("attachment_url")
            .deleteField("status")
            .update()

        try await database.schema(Conversation.schema)
            .deleteField("client_is_unread")
            .deleteField("last_message_preview")
            .deleteField("last_message_at")
            .update()
    }
}
