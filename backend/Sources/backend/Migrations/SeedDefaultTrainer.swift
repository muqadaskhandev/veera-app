import Fluent

struct SeedDefaultTrainer: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let existing = try await Trainer.query(on: database).count()
        guard existing == 0 else { return }

        let trainer = Trainer(
            name: "Jordan Vale",
            title: "Head Strength Coach",
            bio: "Helping driven people get strong, move well, and stay consistent."
        )
        try await trainer.save(on: database)
    }

    func revert(on database: any Database) async throws {
        try await Trainer.query(on: database).delete()
    }
}
