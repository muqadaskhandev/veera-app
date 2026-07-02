import Fluent

struct AddGoalWeightToClient: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("clients")
            .field("goal_weight_kg", .int)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("clients")
            .deleteField("goal_weight_kg")
            .update()
    }
}
