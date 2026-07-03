import Fluent

struct CreatePlatformFeatures: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await MigrationSupport.createTableIfNeeded(FinancialEvent.schema, on: database) { schema in
            schema
                .id()
                .field("trainer_id", .uuid, .required, .references(Trainer.schema, "id", onDelete: .cascade))
                .field("client_id", .uuid, .references(Client.schema, "id", onDelete: .setNull))
                .field("session_id", .uuid, .references(Session.schema, "id", onDelete: .setNull))
                .field("kind", .string, .required)
                .field("title", .string, .required)
                .field("detail", .string, .required)
                .field("amount", .double)
                .field("session_delta", .int, .required)
                .field("occurred_at", .datetime, .required)
                .field("created_at", .datetime)
        }

        try await MigrationSupport.createTableIfNeeded(WeightLog.schema, on: database) { schema in
            schema
                .id()
                .field("client_id", .uuid, .required, .references(Client.schema, "id", onDelete: .cascade))
                .field("logged_by_user_id", .uuid, .references(User.schema, "id", onDelete: .setNull))
                .field("kg", .double, .required)
                .field("recorded_at", .datetime, .required)
                .field("created_at", .datetime)
        }

        try await MigrationSupport.createTableIfNeeded(ProgressPhoto.schema, on: database) { schema in
            schema
                .id()
                .field("client_id", .uuid, .required, .references(Client.schema, "id", onDelete: .cascade))
                .field("image_path", .string, .required)
                .field("captured_at", .datetime, .required)
                .field("created_at", .datetime)
        }

        try await MigrationSupport.createTableIfNeeded(NutritionProfile.schema, on: database) { schema in
            schema
                .id()
                .field("client_id", .uuid, .required, .references(Client.schema, "id", onDelete: .cascade))
                .field("protein_g", .int, .required)
                .field("carbs_g", .int, .required)
                .field("fats_g", .int, .required)
                .field("created_at", .datetime)
                .field("updated_at", .datetime)
                .unique(on: "client_id")
        }

        try await MigrationSupport.createTableIfNeeded(NutritionNote.schema, on: database) { schema in
            schema
                .id()
                .field("client_id", .uuid, .required, .references(Client.schema, "id", onDelete: .cascade))
                .field("text", .string, .required)
                .field("sort_order", .int, .required)
                .field("created_at", .datetime)
        }

        try await MigrationSupport.createTableIfNeeded(Supplement.schema, on: database) { schema in
            schema
                .id()
                .field("client_id", .uuid, .required, .references(Client.schema, "id", onDelete: .cascade))
                .field("name", .string, .required)
                .field("dosage", .string, .required)
                .field("sort_order", .int, .required)
                .field("created_at", .datetime)
        }

        try await MigrationSupport.createTableIfNeeded(WorkoutWeek.schema, on: database) { schema in
            schema
                .id()
                .field("client_id", .uuid, .required, .references(Client.schema, "id", onDelete: .cascade))
                .field("week_index", .int, .required)
                .field("days_json", .string, .required)
                .field("created_at", .datetime)
                .field("updated_at", .datetime)
                .unique(on: "client_id", "week_index")
        }

        try await MigrationSupport.createTableIfNeeded(Exercise.schema, on: database) { schema in
            schema
                .id()
                .field("name", .string, .required)
                .field("category", .string, .required)
                .field("description", .string)
                .field("image_path", .string)
                .field("video_path", .string)
                .field("created_at", .datetime)
                .unique(on: "name")
        }

        try await MigrationSupport.createTableIfNeeded(UserNotification.schema, on: database) { schema in
            schema
                .id()
                .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
                .field("category", .string, .required)
                .field("title", .string, .required)
                .field("body", .string, .required)
                .field("metadata_json", .string)
                .field("read_at", .datetime)
                .field("created_at", .datetime)
        }

        try await MigrationSupport.createTableIfNeeded(NotificationPreferences.schema, on: database) { schema in
            schema
                .id()
                .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
                .field("notify_schedule", .bool, .required)
                .field("notify_messages", .bool, .required)
                .field("notify_activity", .bool, .required)
                .field("sms_enabled", .bool, .required)
                .field("reminder_minutes_before", .int, .required)
                .field("created_at", .datetime)
                .field("updated_at", .datetime)
                .unique(on: "user_id")
        }

        try await MigrationSupport.createTableIfNeeded(ScheduledReminder.schema, on: database) { schema in
            schema
                .id()
                .field("session_id", .uuid, .required, .references(Session.schema, "id", onDelete: .cascade))
                .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
                .field("channel", .string, .required)
                .field("fire_at", .datetime, .required)
                .field("sent_at", .datetime)
                .field("created_at", .datetime)
        }

        try await MigrationSupport.createTableIfNeeded(Subscription.schema, on: database) { schema in
            schema
                .id()
                .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
                .field("product_id", .string, .required)
                .field("original_transaction_id", .string, .required)
                .field("latest_receipt", .string)
                .field("status", .string, .required)
                .field("expires_at", .datetime)
                .field("created_at", .datetime)
                .field("updated_at", .datetime)
                .unique(on: "original_transaction_id")
        }

        try await MigrationSupport.ensureExerciseLibraryColumns(on: database)
        try await MigrationSupport.seedExercisesIfNeeded(on: database)
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Subscription.schema).delete()
        try await database.schema(ScheduledReminder.schema).delete()
        try await database.schema(NotificationPreferences.schema).delete()
        try await database.schema(UserNotification.schema).delete()
        try await database.schema(Exercise.schema).delete()
        try await database.schema(WorkoutWeek.schema).delete()
        try await database.schema(Supplement.schema).delete()
        try await database.schema(NutritionNote.schema).delete()
        try await database.schema(NutritionProfile.schema).delete()
        try await database.schema(ProgressPhoto.schema).delete()
        try await database.schema(WeightLog.schema).delete()
        try await database.schema(FinancialEvent.schema).delete()
    }
}
