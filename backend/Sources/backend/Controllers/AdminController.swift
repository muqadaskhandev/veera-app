import Fluent
import Vapor

struct AdminController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let admin = routes.grouped("api", "admin")
            .grouped(JWTAuthMiddleware())
            .grouped(RoleGuardMiddleware(.admin))

        admin.get("users", use: listUsers)
        admin.patch("users", ":userID", "status", use: setUserStatus)
    }

    @Sendable
    func listUsers(req: Request) async throws -> [UserDTO] {
        try await User.query(on: req.db)
            .sort(\.$createdAt, .descending)
            .all()
            .map(UserDTO.init)
    }

    @Sendable
    func setUserStatus(req: Request) async throws -> UserDTO {
        struct StatusRequest: Content { var isActive: Bool }
        guard let user = try await User.find(req.parameters.get("userID"), on: req.db) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(StatusRequest.self)
        user.isActive = payload.isActive
        try await user.save(on: req.db)
        return try UserDTO(from: user)
    }
}
