import Fluent

struct CreateClient: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Client.schema)
            .id()
            .field("trainer_id", .uuid, .required, .references(Trainer.schema, "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("initials", .string, .required)
            .field("sessions_remaining", .int, .required)
            .field("days_left_on_plan", .int, .required)
            .field("status", .string, .required)
            .field("is_archived", .bool, .required)
            .field("email", .string, .required)
            .field("phone", .string, .required)
            .field("age", .int)
            .field("gender", .string, .required)
            .field("height_cm", .int)
            .field("weight_kg", .int)
            .field("injury_history", .string, .required)
            .field("primary_goal", .string, .required)
            .field("skill_level", .string, .required)
            .field("note", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Client.schema).delete()
    }
}
