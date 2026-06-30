import Fluent
import Vapor

struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("api", "auth")
        auth.post("register", use: register)
        auth.post("verify-email", use: verifyEmail)
        auth.post("verify-email", "resend", use: resendVerificationEmail)
        auth.post("login", use: login)
        auth.post("apple", use: signInWithApple)
        auth.post("google", use: signInWithGoogle)
        auth.post("refresh", use: refresh)
        auth.post("logout", use: logout)
        auth.post("password", "forgot", use: forgotPassword)
        auth.post("password", "reset", use: resetPassword)

        let protected = auth.grouped(JWTAuthMiddleware())
        protected.get("me", use: me)
    }

    @Sendable
    func register(req: Request) async throws -> RegisterResponse {
        let payload = try req.content.decode(RegisterRequest.self)
        guard let role = UserRole(rawValue: payload.role) else {
            throw Abort(.badRequest, reason: "Invalid role. Use trainer, client, or admin.")
        }
        return try await AuthService.register(
            email: payload.email,
            password: payload.password,
            role: role,
            displayName: payload.displayName,
            inviteCode: payload.inviteCode,
            adminSetupSecret: payload.adminSetupSecret,
            on: req
        )
    }

    @Sendable
    func verifyEmail(req: Request) async throws -> AuthTokenResponse {
        let payload = try req.content.decode(VerifyEmailRequest.self)
        return try await AuthService.verifyEmail(code: payload.code, email: payload.email, on: req)
    }

    @Sendable
    func resendVerificationEmail(req: Request) async throws -> ResendVerificationResponse {
        let payload = try req.content.decode(ResendVerificationRequest.self)
        return try await AuthService.resendVerificationEmail(email: payload.email, on: req)
    }

    @Sendable
    func login(req: Request) async throws -> AuthTokenResponse {
        let payload = try req.content.decode(LoginRequest.self)
        return try await AuthService.login(email: payload.email, password: payload.password, on: req)
    }

    @Sendable
    func signInWithGoogle(req: Request) async throws -> AuthTokenResponse {
        let payload = try req.content.decode(GoogleSignInRequest.self)
        guard let role = UserRole(rawValue: payload.role) else {
            throw Abort(.badRequest, reason: "Invalid role. Use trainer, client, or admin.")
        }
        return try await AuthService.signInWithGoogle(
            code: payload.code,
            redirectURI: payload.redirectURI,
            role: role,
            displayName: payload.displayName,
            inviteCode: payload.inviteCode,
            adminSetupSecret: nil,
            on: req
        )
    }

    @Sendable
    func signInWithApple(req: Request) async throws -> AuthTokenResponse {
        let payload = try req.content.decode(AppleSignInRequest.self)
        guard let role = UserRole(rawValue: payload.role) else {
            throw Abort(.badRequest, reason: "Invalid role. Use trainer, client, or admin.")
        }
        return try await AuthService.signInWithApple(
            identityToken: payload.identityToken,
            role: role,
            displayName: payload.displayName,
            inviteCode: payload.inviteCode,
            adminSetupSecret: payload.adminSetupSecret,
            on: req
        )
    }

    @Sendable
    func refresh(req: Request) async throws -> AuthTokenResponse {
        let payload = try req.content.decode(RefreshTokenRequest.self)
        return try await TokenService.refresh(using: payload.refreshToken, on: req)
    }

    @Sendable
    func logout(req: Request) async throws -> MessageResponse {
        let payload = try req.content.decode(RefreshTokenRequest.self)
        try await TokenService.revoke(using: payload.refreshToken, on: req)
        return MessageResponse(message: "Logged out")
    }

    @Sendable
    func forgotPassword(req: Request) async throws -> PasswordResetRequestedResponse {
        let payload = try req.content.decode(ForgotPasswordRequest.self)
        return try await AuthService.requestPasswordReset(email: payload.email, on: req)
    }

    @Sendable
    func resetPassword(req: Request) async throws -> MessageResponse {
        let payload = try req.content.decode(ResetPasswordRequest.self)
        return try await AuthService.resetPassword(
            email: payload.email,
            code: payload.code,
            newPassword: payload.newPassword,
            on: req
        )
    }

    @Sendable
    func me(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        return try UserDTO(from: user)
    }
}
