import Fluent

struct CreateTrainerOnboarding: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(TrainerOnboarding.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("answers_json", .string, .required)
            .field("completed_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(TrainerOnboarding.schema).delete()
    }
}
