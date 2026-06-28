import Fluent

struct CreateEmailVerificationCode: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(EmailVerificationCode.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("code_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("used_at", .datetime)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(EmailVerificationCode.schema).delete()
    }
}
