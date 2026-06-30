import Fluent

struct CreateHealthDailyMetrics: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(HealthDailyMetric.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("date", .date, .required)
            .field("sleep_minutes", .int)
            .field("steps", .int)
            .field("resting_hr", .int)
            .field("hrv", .double)
            .field("active_calories", .int)
            .field("source", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id", "date")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(HealthDailyMetric.schema).delete()
    }
}
