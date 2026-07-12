import Fluent

struct CreateStripePayments: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await MigrationSupport.createTableIfNeeded(StripePayment.schema, on: database) { schema in
            schema
                .id()
                .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
                .field("payment_intent_id", .string, .required)
                .field("stripe_event_id", .string)
                .field("product_type", .string, .required)
                .field("client_id", .uuid, .references(Client.schema, "id", onDelete: .setNull))
                .field("product_id", .string)
                .field("amount", .int, .required)
                .field("currency", .string, .required)
                .field("status", .string, .required)
                .field("session_count", .int)
                .field("created_at", .datetime)
                .field("updated_at", .datetime)
                .unique(on: "payment_intent_id")
        }
    }

    func revert(on database: any Database) async throws {
        try await database.schema(StripePayment.schema).delete()
    }
}
