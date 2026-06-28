import Fluent

struct CreateTrainer: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Trainer.schema)
            .id()
            .field("name", .string, .required)
            .field("title", .string, .required)
            .field("bio", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Trainer.schema).delete()
    }
}
