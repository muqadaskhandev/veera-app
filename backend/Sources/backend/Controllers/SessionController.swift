import Fluent
import Vapor

struct SessionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let sessions = routes.grouped("api", "sessions")
        sessions.get(use: index)
        sessions.post(use: create)
        sessions.get(":sessionID", use: show)
        sessions.delete(":sessionID", use: delete)
    }

    @Sendable
    func index(req: Request) async throws -> [SessionDTO] {
        var query = Session.query(on: req.db).sort(\.$scheduledAt, .ascending)

        if let from = req.query[Date.self, at: "from"] {
            query = query.filter(\.$scheduledAt >= from)
        }
        if let to = req.query[Date.self, at: "to"] {
            query = query.filter(\.$scheduledAt <= to)
        }

        return try await query.all().map(SessionDTO.init)
    }

    @Sendable
    func show(req: Request) async throws -> SessionDTO {
        guard let session = try await Session.find(req.parameters.get("sessionID"), on: req.db) else {
            throw Abort(.notFound)
        }
        return try SessionDTO(from: session)
    }

    @Sendable
    func create(req: Request) async throws -> SessionDTO {
        let payload = try req.content.decode(CreateSessionRequest.self)
        let trainer = try await TrainerService.defaultTrainer(on: req.db)

        let session = Session(
            trainerID: try trainer.requireID(),
            clientID: payload.clientID,
            clientName: payload.clientName,
            focus: payload.focus,
            location: payload.location ?? "",
            accent: payload.accent,
            initials: payload.initials,
            scheduledAt: payload.scheduledAt,
            durationMinutes: payload.durationMinutes ?? 60,
            notes: payload.notes ?? ""
        )
        try await session.save(on: req.db)
        return try SessionDTO(from: session)
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let session = try await Session.find(req.parameters.get("sessionID"), on: req.db) else {
            throw Abort(.notFound)
        }
        try await session.delete(on: req.db)
        return .noContent
    }
}
