import Fluent
import Vapor

struct AddGoogleSubjectToUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(User.schema)
            .field("google_subject", .string)
            .unique(on: "google_subject")
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(User.schema)
            .deleteField("google_subject")
            .update()
    }
}
