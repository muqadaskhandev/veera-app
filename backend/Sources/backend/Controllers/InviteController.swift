import Fluent
import Vapor

struct InviteController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let invites = routes.grouped("api", "invites")
            .grouped(JWTAuthMiddleware())
            .grouped(RoleGuardMiddleware(.trainer, .admin))

        invites.get(use: index)
        invites.post(use: create)
    }

    @Sendable
    func index(req: Request) async throws -> [InviteCodeDTO] {
        let user = try req.auth.require(User.self)

        if user.userRole == .admin {
            return try await InviteCode.query(on: req.db)
                .sort(\.$createdAt, .descending)
                .all()
                .map(InviteCodeDTO.init)
        }

        guard let trainer = try await Trainer.query(on: req.db).filter(\.$user.$id == user.id!).first() else {
            throw Abort(.notFound, reason: "Trainer profile not found")
        }

        return try await InviteCode.query(on: req.db)
            .filter(\.$trainer.$id == trainer.id!)
            .sort(\.$createdAt, .descending)
            .all()
            .map(InviteCodeDTO.init)
    }

    @Sendable
    func create(req: Request) async throws -> InviteCodeDTO {
        let user = try req.auth.require(User.self)
        struct CreateInviteRequest: Content { var expiresInDays: Int? }
        let payload = try req.content.decode(CreateInviteRequest.self)

        guard let trainer = try await Trainer.query(on: req.db).filter(\.$user.$id == user.id!).first() else {
            throw Abort(.notFound, reason: "Trainer profile not found")
        }

        let invite = try await InviteService.createInvite(
            for: trainer,
            createdBy: user,
            expiresInDays: payload.expiresInDays,
            on: req.db
        )
        return try InviteCodeDTO(from: invite)
    }
}
