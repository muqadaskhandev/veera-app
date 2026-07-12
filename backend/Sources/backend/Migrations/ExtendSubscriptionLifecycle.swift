import Fluent

struct ExtendSubscriptionLifecycle: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard try await MigrationSupport.tableExists(Subscription.schema, on: database) else { return }

        if try await !MigrationSupport.columnExists("started_at", on: Subscription.schema, database: database) {
            try await database.schema(Subscription.schema)
                .field("started_at", .datetime)
                .update()
        }

        if try await !MigrationSupport.columnExists("expiry_notified_at", on: Subscription.schema, database: database) {
            try await database.schema(Subscription.schema)
                .field("expiry_notified_at", .datetime)
                .update()
        }
    }

    func revert(on database: any Database) async throws {
        guard try await MigrationSupport.tableExists(Subscription.schema, on: database) else { return }

        if try await MigrationSupport.columnExists("expiry_notified_at", on: Subscription.schema, database: database) {
            try await database.schema(Subscription.schema)
                .deleteField("expiry_notified_at")
                .update()
        }

        if try await MigrationSupport.columnExists("started_at", on: Subscription.schema, database: database) {
            try await database.schema(Subscription.schema)
                .deleteField("started_at")
                .update()
        }
    }
}
