import Fluent

struct AddUserForeignKeys: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Trainer.schema)
            .field("user_id", .uuid, .references(User.schema, "id", onDelete: .setNull))
            .unique(on: "user_id")
            .update()

        try await database.schema(Client.schema)
            .field("user_id", .uuid, .references(User.schema, "id", onDelete: .setNull))
            .unique(on: "user_id")
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Trainer.schema)
            .deleteField("user_id")
            .update()

        try await database.schema(Client.schema)
            .deleteField("user_id")
            .update()
    }
}
