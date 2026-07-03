import Fluent
import SQLKit

enum MigrationSupport {
    static func tableExists(_ table: String, on database: any Database) async throws -> Bool {
        guard let sql = database as? any SQLDatabase else { return false }
        let rows = try await sql.raw(
            """
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = \(bind: table)
            LIMIT 1
            """
        ).all()
        return !rows.isEmpty
    }

    static func columnExists(_ name: String, on table: String, database: any Database) async throws -> Bool {
        guard let sql = database as? any SQLDatabase else { return false }
        let rows = try await sql.raw(
            """
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = \(bind: table) AND column_name = \(bind: name)
            LIMIT 1
            """
        ).all()
        return !rows.isEmpty
    }

    static func createTableIfNeeded(_ table: String, on database: any Database, build: (SchemaBuilder) -> SchemaBuilder) async throws {
        guard try await !tableExists(table, on: database) else { return }
        try await build(database.schema(table)).create()
    }

    static func ensureExerciseLibraryColumns(on database: any Database) async throws {
        guard try await tableExists(Exercise.schema, on: database) else { return }
        guard try await !columnExists("description", on: Exercise.schema, database: database) else { return }
        try await database.schema(Exercise.schema)
            .field("description", .string)
            .field("image_path", .string)
            .field("video_path", .string)
            .update()
    }

    static func seedExercisesIfNeeded(on database: any Database) async throws {
        for entry in ExerciseSeed.metadata {
            if try await Exercise.query(on: database).filter(\.$name == entry.name).first() != nil {
                continue
            }
            let exercise = Exercise(name: entry.name, category: entry.category, description: entry.description)
            try await exercise.save(on: database)
        }
    }
}
