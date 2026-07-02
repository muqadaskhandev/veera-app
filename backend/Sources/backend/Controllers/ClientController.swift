import Fluent
import Vapor

struct ClientController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let clients = routes.grouped("api", "clients")
            .grouped(JWTAuthMiddleware())

        clients.get(use: index)
        clients.post(use: create)
        clients.get(":clientID", use: show)
        clients.patch(":clientID", use: update)
        clients.delete(":clientID", use: delete)
    }

    @Sendable
    func index(req: Request) async throws -> [ClientDTO] {
        let user = try req.auth.require(User.self)
        let archived = req.query[Bool.self, at: "archived"] ?? false

        var query = Client.query(on: req.db)
            .filter(\.$isArchived == archived)
            .sort(\.$name, .ascending)

        if user.userRole != .admin {
            guard let trainer = try await Trainer.query(on: req.db)
                .filter(\.$user.$id == user.id!)
                .first() else {
                throw Abort(.notFound, reason: "Trainer profile not found")
            }
            query = query.filter(\.$trainer.$id == trainer.id!)
        }

        return try await query.all().map(ClientDTO.init)
    }

    @Sendable
    func show(req: Request) async throws -> ClientDTO {
        let client = try await requireClient(req)
        return try ClientDTO(from: client)
    }

    @Sendable
    func create(req: Request) async throws -> ClientDTO {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(CreateClientRequest.self)
        let trainer = try await trainer(for: user, on: req.db)

        let initials = payload.initials ?? Self.initials(from: payload.name)
        let client = Client(
            trainerID: try trainer.requireID(),
            name: payload.name,
            initials: initials,
            sessionsRemaining: payload.sessionsRemaining ?? 0,
            daysLeftOnPlan: payload.daysLeftOnPlan ?? 30,
            status: payload.status ?? "active",
            email: payload.email ?? "",
            phone: payload.phone ?? "",
            age: payload.age,
            gender: payload.gender ?? "",
            heightCm: payload.heightCm,
            weightKg: payload.weightKg,
            injuryHistory: payload.injuryHistory ?? "",
            primaryGoal: payload.primaryGoal ?? "",
            skillLevel: payload.skillLevel ?? "",
            note: payload.note ?? ""
        )
        try await client.save(on: req.db)
        return try ClientDTO(from: client)
    }

    @Sendable
    func update(req: Request) async throws -> ClientDTO {
        let client = try await requireClient(req)
        let payload = try req.content.decode(UpdateClientRequest.self)
        if let name = payload.name { client.name = name }
        if let initials = payload.initials { client.initials = initials }
        if let sessionsRemaining = payload.sessionsRemaining { client.sessionsRemaining = sessionsRemaining }
        if let daysLeftOnPlan = payload.daysLeftOnPlan { client.daysLeftOnPlan = daysLeftOnPlan }
        if let status = payload.status { client.status = status }
        if let isArchived = payload.isArchived { client.isArchived = isArchived }
        if let email = payload.email { client.email = email }
        if let phone = payload.phone { client.phone = phone }
        if let age = payload.age { client.age = age }
        if let gender = payload.gender { client.gender = gender }
        if let heightCm = payload.heightCm { client.heightCm = heightCm }
        if let weightKg = payload.weightKg { client.weightKg = weightKg }
        if let injuryHistory = payload.injuryHistory { client.injuryHistory = injuryHistory }
        if let primaryGoal = payload.primaryGoal { client.primaryGoal = primaryGoal }
        if let skillLevel = payload.skillLevel { client.skillLevel = skillLevel }
        if let note = payload.note { client.note = note }

        try await client.save(on: req.db)
        return try ClientDTO(from: client)
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let client = try await requireClient(req)
        try await client.delete(on: req.db)
        return .noContent
    }

    private func requireClient(_ req: Request) async throws -> Client {
        let user = try req.auth.require(User.self)
        guard let client = try await Client.find(req.parameters.get("clientID"), on: req.db) else {
            throw Abort(.notFound)
        }

        if user.userRole != .admin {
            guard let trainer = try await Trainer.query(on: req.db)
                .filter(\.$user.$id == user.id!)
                .first(),
                client.$trainer.id == trainer.id else {
                throw Abort(.forbidden)
            }
        }

        return client
    }

    private func trainer(for user: User, on database: any Database) async throws -> Trainer {
        if user.userRole == .admin {
            return try await TrainerService.defaultTrainer(on: database)
        }
        guard let trainer = try await Trainer.query(on: database)
            .filter(\.$user.$id == user.id!)
            .first() else {
            throw Abort(.notFound, reason: "Trainer profile not found")
        }
        return trainer
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }
}
