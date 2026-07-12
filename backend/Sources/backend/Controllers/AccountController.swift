import Fluent
import Vapor

struct AccountController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let account = routes.grouped("api", "account")
            .grouped(JWTAuthMiddleware())

        account.patch("password", use: changePassword)
        account.delete(use: deleteAccount)
        account.post("support", use: submitSupport)
    }

    @Sendable
    func changePassword(req: Request) async throws -> MessageResponse {
        let user = try req.auth.require(User.self)
        struct Body: Content {
            var currentPassword: String
            var newPassword: String
        }
        let body = try req.content.decode(Body.self)
        try await AccountService.changePassword(
            for: user,
            currentPassword: body.currentPassword,
            newPassword: body.newPassword,
            on: req.db
        )
        return MessageResponse(message: "Password updated successfully")
    }

    @Sendable
    func deleteAccount(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        try await AccountService.deleteAccount(for: user, on: req.db)
        return .noContent
    }

    @Sendable
    func submitSupport(req: Request) async throws -> SupportTicketDTO {
        let user = try req.auth.require(User.self)

        struct SupportUpload: Content {
            var topic: String
            var message: String
            var attachment: File?
        }

        let upload = try req.content.decode(SupportUpload.self)
        return try await AccountService.submitSupportTicket(
            for: user,
            topic: upload.topic,
            message: upload.message,
            attachment: upload.attachment,
            on: req.db,
            app: req.application
        )
    }
}
