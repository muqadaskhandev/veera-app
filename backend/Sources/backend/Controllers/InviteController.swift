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
    func create(req: Request) async throws -> InviteCreatedResponse {
        let user = try req.auth.require(User.self)
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

        var emailSent = false
        if let rawEmail = payload.clientEmail, !rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let email = try ClientInviteEmailService.normalizeEmail(rawEmail)
            ClientInviteEmailService.queueInvite(
                to: email,
                trainerName: trainer.name,
                clientName: payload.clientName,
                code: invite.code,
                expiresAt: invite.expiresAt,
                on: req.application
            )
            emailSent = true
        }

        return InviteCreatedResponse(
            invite: try InviteCodeDTO(from: invite),
            emailSent: emailSent
        )
    }
}
