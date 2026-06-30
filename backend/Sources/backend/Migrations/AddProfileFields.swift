import Fluent
import FluentSQL

struct AddProfileFields: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            try await database.schema(User.schema)
                .field("avatar_path", .string)
                .update()
            try await database.schema(Trainer.schema)
                .field("specialties_json", .string)
                .update()
            return
        }

        try await sql.raw(#"ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "avatar_path" TEXT"#).run()
        try await sql.raw(#"ALTER TABLE "trainers" ADD COLUMN IF NOT EXISTS "specialties_json" TEXT"#).run()
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            try await database.schema(User.schema)
                .deleteField("avatar_path")
                .update()
            try await database.schema(Trainer.schema)
                .deleteField("specialties_json")
                .update()
            return
        }

        try await sql.raw(#"ALTER TABLE "users" DROP COLUMN IF EXISTS "avatar_path""#).run()
        try await sql.raw(#"ALTER TABLE "trainers" DROP COLUMN IF EXISTS "specialties_json""#).run()
    }
}
