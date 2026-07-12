import Fluent
import FluentSQL

struct ExtendPlatformSettings: AsyncMigration {
    func prepare(on database: any Database) async throws {
        if try await MigrationSupport.tableExists(NotificationPreferences.schema, on: database),
           try await !MigrationSupport.columnExists("notifications_enabled", on: NotificationPreferences.schema, database: database) {
            if let sql = database as? any SQLDatabase {
                try await sql.raw(#"ALTER TABLE "notification_preferences" ADD COLUMN IF NOT EXISTS "notifications_enabled" BOOLEAN NOT NULL DEFAULT TRUE"#).run()
                try await sql.raw(#"ALTER TABLE "notification_preferences" ADD COLUMN IF NOT EXISTS "notify_money" BOOLEAN NOT NULL DEFAULT TRUE"#).run()
                try await sql.raw(#"ALTER TABLE "notification_preferences" ADD COLUMN IF NOT EXISTS "activity_mode" TEXT NOT NULL DEFAULT 'personalBests'"#).run()
                try await sql.raw(#"ALTER TABLE "notification_preferences" ADD COLUMN IF NOT EXISTS "quiet_hours_enabled" BOOLEAN NOT NULL DEFAULT TRUE"#).run()
                try await sql.raw(#"ALTER TABLE "notification_preferences" ADD COLUMN IF NOT EXISTS "quiet_start_minutes" INTEGER NOT NULL DEFAULT 1320"#).run()
                try await sql.raw(#"ALTER TABLE "notification_preferences" ADD COLUMN IF NOT EXISTS "quiet_end_minutes" INTEGER NOT NULL DEFAULT 360"#).run()
            } else {
                try await database.schema(NotificationPreferences.schema)
                    .field("notifications_enabled", .bool, .required)
                    .field("notify_money", .bool, .required)
                    .field("activity_mode", .string, .required)
                    .field("quiet_hours_enabled", .bool, .required)
                    .field("quiet_start_minutes", .int, .required)
                    .field("quiet_end_minutes", .int, .required)
                    .update()
            }
        }

        try await MigrationSupport.createTableIfNeeded(SupportTicket.schema, on: database) { schema in
            schema
                .id()
                .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
                .field("topic", .string, .required)
                .field("message", .string, .required)
                .field("attachment_path", .string)
                .field("status", .string, .required)
                .field("created_at", .datetime)
        }
    }

    func revert(on database: any Database) async throws {
        if try await MigrationSupport.tableExists(SupportTicket.schema, on: database) {
            try await database.schema(SupportTicket.schema).delete()
        }
        if try await MigrationSupport.tableExists(NotificationPreferences.schema, on: database),
           try await MigrationSupport.columnExists("notifications_enabled", on: NotificationPreferences.schema, database: database) {
            if let sql = database as? any SQLDatabase {
                try await sql.raw(#"ALTER TABLE "notification_preferences" DROP COLUMN IF EXISTS "notifications_enabled""#).run()
                try await sql.raw(#"ALTER TABLE "notification_preferences" DROP COLUMN IF EXISTS "notify_money""#).run()
                try await sql.raw(#"ALTER TABLE "notification_preferences" DROP COLUMN IF EXISTS "activity_mode""#).run()
                try await sql.raw(#"ALTER TABLE "notification_preferences" DROP COLUMN IF EXISTS "quiet_hours_enabled""#).run()
                try await sql.raw(#"ALTER TABLE "notification_preferences" DROP COLUMN IF EXISTS "quiet_start_minutes""#).run()
                try await sql.raw(#"ALTER TABLE "notification_preferences" DROP COLUMN IF EXISTS "quiet_end_minutes""#).run()
            } else {
                try await database.schema(NotificationPreferences.schema)
                    .deleteField("notifications_enabled")
                    .deleteField("notify_money")
                    .deleteField("activity_mode")
                    .deleteField("quiet_hours_enabled")
                    .deleteField("quiet_start_minutes")
                    .deleteField("quiet_end_minutes")
                    .update()
            }
        }
    }
}
