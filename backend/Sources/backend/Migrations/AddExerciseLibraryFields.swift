import Fluent

struct AddExerciseLibraryFields: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await MigrationSupport.ensureExerciseLibraryColumns(on: database)

        for entry in ExerciseSeed.metadata {
            guard let exercise = try await Exercise.query(on: database)
                .filter(\.$name == entry.name)
                .first() else { continue }
            exercise.category = entry.category
            exercise.description = entry.description
            try await exercise.save(on: database)
        }
    }

    func revert(on database: any Database) async throws {
        if try await MigrationSupport.columnExists("description", on: Exercise.schema, database: database) {
            try await database.schema(Exercise.schema)
                .deleteField("description")
                .deleteField("image_path")
                .deleteField("video_path")
                .update()
        }
    }
}

enum ExerciseSeed {
    struct Entry {
        let name: String
        let category: String
        let description: String
    }

    static let metadata: [Entry] = [
        Entry(name: "Back Squat", category: "strength", description: "Barbell squat with the bar on your upper back. Primary lower-body strength builder."),
        Entry(name: "Front Squat", category: "strength", description: "Squat variation with the bar in the front rack. Emphasizes quads and upright torso."),
        Entry(name: "Bench Press", category: "strength", description: "Horizontal pressing movement for chest, shoulders, and triceps."),
        Entry(name: "Incline Bench Press", category: "strength", description: "Incline pressing variation targeting upper chest and shoulders."),
        Entry(name: "Deadlift", category: "strength", description: "Hip-hinge lift developing posterior chain strength."),
        Entry(name: "Romanian Deadlift", category: "strength", description: "Hinge pattern with minimal knee bend, focusing on hamstrings and glutes."),
        Entry(name: "Overhead Press", category: "strength", description: "Strict vertical press for shoulders and triceps."),
        Entry(name: "Pull-Ups", category: "strength", description: "Bodyweight vertical pull for lats and upper back."),
        Entry(name: "Chin-Ups", category: "strength", description: "Supinated pull-up variation with extra biceps involvement."),
        Entry(name: "Barbell Row", category: "strength", description: "Horizontal row for mid-back thickness and pulling strength."),
        Entry(name: "Lat Pulldown", category: "accessory", description: "Cable pulldown for lat development and pull-up progression."),
        Entry(name: "Walking Lunge", category: "accessory", description: "Single-leg lunge pattern for legs and balance."),
        Entry(name: "Bulgarian Split Squat", category: "accessory", description: "Rear-foot elevated split squat for unilateral leg strength."),
        Entry(name: "Leg Press", category: "accessory", description: "Machine-based quad and glute pressing movement."),
        Entry(name: "Hip Thrust", category: "accessory", description: "Glute-focused hip extension, usually with a barbell."),
        Entry(name: "Face Pull", category: "accessory", description: "Cable rear-delt and upper-back exercise for shoulder health."),
        Entry(name: "Lateral Raise", category: "accessory", description: "Isolation movement for side delts."),
        Entry(name: "Bicep Curl", category: "accessory", description: "Elbow flexion exercise for biceps."),
        Entry(name: "Tricep Pushdown", category: "accessory", description: "Cable triceps extension for arm size and lockout strength."),
        Entry(name: "Plank", category: "mobility", description: "Isometric core bracing hold for trunk stability."),
        Entry(name: "Hanging Leg Raise", category: "mobility", description: "Core flexion from a dead hang targeting lower abs."),
        Entry(name: "Kettlebell Swing", category: "conditioning", description: "Explosive hip hinge for power and conditioning."),
        Entry(name: "Assault Bike", category: "cardio", description: "Full-body air bike intervals for aerobic and anaerobic capacity."),
        Entry(name: "Box Jump", category: "conditioning", description: "Plyometric jump onto a box for power and athleticism."),
    ]
}
