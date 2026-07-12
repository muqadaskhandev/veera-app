import Fluent
import Foundation
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

    /// Fills week 0 for clients that have no workout plan yet (dev / empty DB).
    static func seedSampleWorkoutsIfNeeded(on database: any Database) async throws {
        guard try await tableExists(WorkoutWeek.schema, on: database) else { return }

        let exercises = try await Exercise.query(on: database).all()
        guard !exercises.isEmpty else { return }

        func payload(_ name: String, sets: Int, reps: Int) -> WorkoutExercisePayload? {
            guard let match = exercises.first(where: { $0.name == name }), let id = match.id else { return nil }
            return WorkoutExercisePayload(
                id: UUID(),
                exerciseID: id,
                name: match.name,
                category: match.category,
                sets: sets,
                reps: reps,
                kind: "exercise"
            )
        }

        func day(_ label: String, focus: String?, names: [(String, Int, Int)]) -> WorkoutDayPayload {
            let items = names.compactMap { payload($0.0, sets: $0.1, reps: $0.2) }
            return WorkoutDayPayload(id: UUID(), label: label, focus: focus, exercises: items)
        }

        let sampleDays: [WorkoutDayPayload] = [
            day("Mon", focus: "Lower strength", names: [
                ("Back Squat", 4, 6),
                ("Romanian Deadlift", 3, 8),
                ("Bulgarian Split Squat", 3, 10),
                ("Plank", 3, 45),
            ]),
            day("Tue", focus: "Upper push", names: [
                ("Bench Press", 4, 6),
                ("Overhead Press", 3, 8),
                ("Lateral Raise", 3, 12),
                ("Tricep Pushdown", 3, 12),
            ]),
            WorkoutDayPayload(id: UUID(), label: "Wed", focus: "Recovery", exercises: [
                WorkoutExercisePayload(id: UUID(), exerciseID: nil, name: "Rest Day", category: nil, sets: nil, reps: nil, kind: "rest"),
            ]),
            day("Thu", focus: "Upper pull", names: [
                ("Pull-Ups", 4, 6),
                ("Barbell Row", 4, 8),
                ("Lat Pulldown", 3, 10),
                ("Face Pull", 3, 15),
                ("Bicep Curl", 3, 12),
            ]),
            day("Fri", focus: "Posterior chain", names: [
                ("Deadlift", 3, 5),
                ("Hip Thrust", 3, 10),
                ("Walking Lunge", 3, 10),
                ("Kettlebell Swing", 3, 15),
            ]),
            day("Sat", focus: "Conditioning", names: [
                ("Assault Bike", 1, 20),
                ("Box Jump", 4, 6),
                ("Hanging Leg Raise", 3, 10),
            ]),
            WorkoutDayPayload(id: UUID(), label: "Sun", focus: "Off", exercises: [
                WorkoutExercisePayload(id: UUID(), exerciseID: nil, name: "Rest Day", category: nil, sets: nil, reps: nil, kind: "rest"),
            ]),
        ]

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(sampleDays),
              let json = String(data: data, encoding: .utf8) else { return }

        let clients = try await Client.query(on: database).all()
        for client in clients {
            guard let clientID = client.id else { continue }
            let existing = try await WorkoutWeek.query(on: database)
                .filter(\.$client.$id == clientID)
                .count()
            guard existing == 0 else { continue }
            let week = WorkoutWeek(clientID: clientID, weekIndex: 0, daysJSON: json)
            try await week.save(on: database)
        }
    }
}
