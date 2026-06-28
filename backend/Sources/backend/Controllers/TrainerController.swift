import Fluent
import Vapor

enum TrainerService {
    static func defaultTrainer(on database: any Database) async throws -> Trainer {
        guard let trainer = try await Trainer.query(on: database).first() else {
            throw Abort(.notFound, reason: "No trainer found. Run migrations first.")
        }
        return trainer
    }
}

struct TrainerController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let trainers = routes.grouped("api", "trainers")
        trainers.get(use: index)
        trainers.get(":trainerID", use: show)
    }

    @Sendable
    func index(req: Request) async throws -> [TrainerDTO] {
        try await Trainer.query(on: req.db).all().map(TrainerDTO.init)
    }

    @Sendable
    func show(req: Request) async throws -> TrainerDTO {
        guard let trainer = try await Trainer.find(req.parameters.get("trainerID"), on: req.db) else {
            throw Abort(.notFound)
        }
        return try TrainerDTO(from: trainer)
    }
}
