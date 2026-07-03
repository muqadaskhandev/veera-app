import Fluent

struct AddVisibleModulesToClient: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("clients")
            .field("visible_modules_json", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("clients")
            .deleteField("visible_modules_json")
            .update()
    }
}
