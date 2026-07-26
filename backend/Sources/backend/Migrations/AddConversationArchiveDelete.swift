import Fluent
import SQLKit

struct AddConversationArchiveDelete: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Conversation.schema)
            .field("trainer_is_archived", .bool)
            .field("client_is_archived", .bool)
            .field("trainer_is_deleted", .bool)
            .field("client_is_deleted", .bool)
            .update()

        if let sql = database as? any SQLDatabase {
            try await sql.raw("""
                UPDATE conversations
                SET trainer_is_archived = COALESCE(trainer_is_archived, false),
                    client_is_archived = COALESCE(client_is_archived, false),
                    trainer_is_deleted = COALESCE(trainer_is_deleted, false),
                    client_is_deleted = COALESCE(client_is_deleted, false)
                """).run()
        }
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Conversation.schema)
            .deleteField("trainer_is_archived")
            .deleteField("client_is_archived")
            .deleteField("trainer_is_deleted")
            .deleteField("client_is_deleted")
            .update()
    }
}
