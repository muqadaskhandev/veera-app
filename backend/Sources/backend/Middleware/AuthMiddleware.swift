import Fluent
import JWT
import Vapor

struct JWTAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let bearer = request.headers.bearerAuthorization else {
            throw Abort(.unauthorized, reason: "Missing bearer token")
        }

        let payload = try request.jwt.verify(bearer.token, as: AccessTokenPayload.self)
        guard let userID = UUID(uuidString: payload.subject.value),
              let user = try await User.find(userID, on: request.db),
              user.isActive else {
            throw Abort(.unauthorized, reason: "Invalid session")
        }

        request.auth.login(user)
        return try await next.respond(to: request)
    }
}

struct RoleGuardMiddleware: AsyncMiddleware {
    let allowedRoles: Set<UserRole>

    init(_ roles: UserRole...) {
        self.allowedRoles = Set(roles)
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let user = try request.auth.require(User.self)
        guard let role = user.userRole, allowedRoles.contains(role) else {
            throw Abort(.forbidden, reason: "Insufficient permissions")
        }
        return try await next.respond(to: request)
    }
}
