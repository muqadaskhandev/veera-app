import Crypto
import Fluent
import JWTKit
import Vapor

enum AuthService {
    static func register(
        email: String,
        password: String,
        role: UserRole,
        displayName: String,
        inviteCode: String?,
        adminSetupSecret: String?,
        on request: Request
    ) async throws -> RegisterResponse {
        try validatePassword(password)
        try await assertRoleAllowed(role, adminSetupSecret: adminSetupSecret)

        let normalizedEmail = email.lowercased()
        if try await User.query(on: request.db).filter(\.$email == normalizedEmail).first() != nil {
            throw Abort(.conflict, reason: "Email already registered")
        }

        let user = User(
            email: normalizedEmail,
            passwordHash: try Bcrypt.hash(password),
            role: role,
            displayName: displayName,
            isEmailVerified: false
        )
        try await user.save(on: request.db)

        switch role {
        case .trainer:
            try await createTrainerProfile(for: user, on: request.db)
        case .client:
            try await redeemInviteAndCreateClient(for: user, inviteCode: inviteCode, displayName: displayName, on: request)
        case .admin:
            break
        }

        let code = try await EmailVerificationService.issueCode(for: user, on: request.db)
        try await EmailVerificationService.sendVerificationCode(to: normalizedEmail, code: code, on: request)

        let isDevelopment = request.application.environment == .development
        let sesConfigured = SESEmailService.isConfigured()
        return .pending(email: normalizedEmail, devCode: (isDevelopment && !sesConfigured) ? code : nil)
    }

    static func verifyEmail(code: String, email: String, on request: Request) async throws -> AuthTokenResponse {
        let user = try await EmailVerificationService.verify(code: code, email: email, on: request.db)
        return try await TokenService.issueTokens(for: user, on: request)
    }

    static func resendVerificationEmail(email: String, on request: Request) async throws -> ResendVerificationResponse {
        let normalizedEmail = email.lowercased()
        guard let user = try await User.query(on: request.db).filter(\.$email == normalizedEmail).first() else {
            return ResendVerificationResponse(message: "If that email exists, a new code was sent.", devCode: nil)
        }
        guard !user.isEmailVerified else {
            return ResendVerificationResponse(message: "Email is already verified.", devCode: nil)
        }

        let code = try await EmailVerificationService.issueCode(for: user, on: request.db)
        try await EmailVerificationService.sendVerificationCode(to: normalizedEmail, code: code, on: request)
        let isDevelopment = request.application.environment == .development
        let sesConfigured = SESEmailService.isConfigured()
        return ResendVerificationResponse(
            message: "If that email exists, a new code was sent.",
            devCode: (isDevelopment && !sesConfigured) ? code : nil
        )
    }

    static func login(email: String, password: String, on request: Request) async throws -> AuthTokenResponse {
        let normalizedEmail = email.lowercased()
        guard let user = try await User.query(on: request.db).filter(\.$email == normalizedEmail).first() else {
            throw Abort(.unauthorized, reason: "Invalid email or password")
        }
        guard user.isActive else {
            throw Abort(.forbidden, reason: "Account is inactive")
        }
        guard let passwordHash = user.passwordHash, try Bcrypt.verify(password, created: passwordHash) else {
            throw Abort(.unauthorized, reason: "Invalid email or password")
        }
        guard user.isEmailVerified else {
            throw Abort(.forbidden, reason: "Please verify your email before signing in")
        }
        return try await TokenService.issueTokens(for: user, on: request)
    }

    static func signInWithApple(
        identityToken: String,
        role: UserRole,
        displayName: String?,
        inviteCode: String?,
        adminSetupSecret: String?,
        on request: Request
    ) async throws -> AuthTokenResponse {
        try await assertRoleAllowed(role, adminSetupSecret: adminSetupSecret)
        let claims = try await AppleAuthService.verify(identityToken: identityToken, on: request.application)
        let appleSubject = claims.subject.value

        if let existing = try await User.query(on: request.db)
            .filter(\.$appleSubject == appleSubject)
            .first() {
            guard existing.isActive else { throw Abort(.forbidden, reason: "Account is inactive") }
            return try await TokenService.issueTokens(for: existing, on: request)
        }

        if let email = claims.email?.lowercased(),
           let existingByEmail = try await User.query(on: request.db).filter(\.$email == email).first() {
            existingByEmail.appleSubject = appleSubject
            existingByEmail.isEmailVerified = claims.emailVerified ?? true
            try await existingByEmail.save(on: request.db)
            return try await TokenService.issueTokens(for: existingByEmail, on: request)
        }

        let user = User(
            email: claims.email?.lowercased(),
            passwordHash: nil,
            role: role,
            appleSubject: appleSubject,
            displayName: displayName ?? claims.email ?? "Verra User",
            isEmailVerified: true
        )
        try await user.save(on: request.db)

        switch role {
        case .trainer:
            try await createTrainerProfile(for: user, on: request.db)
        case .client:
            try await redeemInviteAndCreateClient(for: user, inviteCode: inviteCode, displayName: user.displayName, on: request)
        case .admin:
            break
        }

        return try await TokenService.issueTokens(for: user, on: request)
    }

    static func signInWithGoogle(
        code: String,
        redirectURI: String,
        role: UserRole,
        displayName: String?,
        inviteCode: String?,
        adminSetupSecret: String?,
        on request: Request
    ) async throws -> AuthTokenResponse {
        try await assertRoleAllowed(role, adminSetupSecret: adminSetupSecret)
        let info = try await GoogleAuthService.exchangeAndVerify(
            code: code,
            redirectURI: redirectURI,
            on: request.application
        )

        if let existing = try await User.query(on: request.db)
            .filter(\.$googleSubject == info.sub)
            .first() {
            guard existing.isActive else { throw Abort(.forbidden, reason: "Account is inactive") }
            return try await TokenService.issueTokens(for: existing, on: request)
        }

        if let email = info.email?.lowercased(),
           let existingByEmail = try await User.query(on: request.db).filter(\.$email == email).first() {
            existingByEmail.googleSubject = info.sub
            existingByEmail.isEmailVerified = info.isEmailVerified
            try await existingByEmail.save(on: request.db)
            return try await TokenService.issueTokens(for: existingByEmail, on: request)
        }

        let user = User(
            email: info.email?.lowercased(),
            passwordHash: nil,
            role: role,
            googleSubject: info.sub,
            displayName: displayName ?? info.email ?? "Verra User",
            isEmailVerified: info.isEmailVerified
        )
        try await user.save(on: request.db)

        switch role {
        case .trainer:
            try await createTrainerProfile(for: user, on: request.db)
        case .client:
            try await redeemInviteAndCreateClient(for: user, inviteCode: inviteCode, displayName: user.displayName, on: request)
        case .admin:
            break
        }

        return try await TokenService.issueTokens(for: user, on: request)
    }

    static func requestPasswordReset(email: String, on request: Request) async throws -> PasswordResetRequestedResponse {
        let normalizedEmail = email.lowercased()
        guard let user = try await User.query(on: request.db).filter(\.$email == normalizedEmail).first(),
              user.passwordHash != nil else {
            return PasswordResetRequestedResponse(message: "If that email exists, a reset link was sent.")
        }

        let rawToken = [UInt8].random(count: 32).base64
        let tokenHash = SHA256.hash(data: Data(rawToken.utf8)).hex
        let reset = PasswordResetToken(
            userID: try user.requireID(),
            tokenHash: tokenHash,
            expiresAt: Date().addingTimeInterval(60 * 60)
        )
        try await reset.save(on: request.db)

        let resetBase = Environment.get("PASSWORD_RESET_URL") ?? "https://verraos.app/reset-password"
        let encodedToken = rawToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawToken
        let resetLink = "\(resetBase)?token=\(encodedToken)"
        let subject = "Reset your Verra password"
        let textBody = """
        We received a request to reset your Verra password.

        Open this link to choose a new password:
        \(resetLink)

        This link expires in 1 hour.
        If you did not request this, you can ignore this email.
        """
        let htmlBody = """
        <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#111;">
          <p>We received a request to reset your Verra password.</p>
          <p><a href="\(resetLink)" style="color:#1a7f37;font-weight:600;">Reset your password</a></p>
          <p style="color:#555;">This link expires in 1 hour.</p>
          <p style="color:#555;">If you did not request this, you can ignore this email.</p>
        </div>
        """
        try await SESEmailService.send(
            to: normalizedEmail,
            subject: subject,
            textBody: textBody,
            htmlBody: htmlBody,
            on: request
        )

        let isDevelopment = request.application.environment == .development
        let sesConfigured = SESEmailService.isConfigured()
        return PasswordResetRequestedResponse(
            message: "If that email exists, a reset link was sent.",
            resetToken: (isDevelopment && !sesConfigured) ? rawToken : nil
        )
    }

    static func resetPassword(token: String, newPassword: String, on request: Request) async throws -> MessageResponse {
        try validatePassword(newPassword)
        let tokenHash = SHA256.hash(data: Data(token.utf8)).hex

        guard let reset = try await PasswordResetToken.query(on: request.db)
            .filter(\.$tokenHash == tokenHash)
            .first(),
            reset.isValid else {
            throw Abort(.badRequest, reason: "Invalid or expired reset token")
        }

        let user = try await reset.$user.get(on: request.db)
        user.passwordHash = try Bcrypt.hash(newPassword)
        reset.usedAt = Date()
        try await user.save(on: request.db)
        try await reset.save(on: request.db)

        return MessageResponse(message: "Password updated successfully")
    }

    private static func createTrainerProfile(for user: User, on database: any Database) async throws {
        let trainer = Trainer(
            name: user.displayName,
            title: "Strength Coach",
            bio: ""
        )
        trainer.$user.id = try user.requireID()
        try await trainer.save(on: database)
    }

    static func linkClientToInvite(
        user: User,
        inviteCode: String,
        displayName: String,
        primaryGoal: String,
        on database: any Database
    ) async throws {
        let invite = try await InviteCode.query(on: database)
            .filter(\.$code == inviteCode.uppercased())
            .with(\.$trainer)
            .first()

        guard let invite, invite.isRedeemable else {
            throw Abort(.badRequest, reason: "Invalid or expired invite code")
        }

        let trainer = try await invite.$trainer.get(on: database)
        let client = Client(
            trainerID: try trainer.requireID(),
            name: displayName,
            initials: initials(from: displayName),
            sessionsRemaining: 0,
            status: "pending",
            primaryGoal: primaryGoal
        )
        client.$user.id = try user.requireID()
        try await client.save(on: database)

        invite.redeemedAt = Date()
        invite.$redeemedByUser.id = try user.requireID()
        invite.$client.id = try client.requireID()
        try await invite.save(on: database)
    }

    private static func redeemInviteAndCreateClient(
        for user: User,
        inviteCode: String?,
        displayName: String,
        on request: Request
    ) async throws {
        guard let inviteCode, !inviteCode.isEmpty else {
            throw Abort(.badRequest, reason: "Invite code is required for client registration")
        }
        try await linkClientToInvite(
            user: user,
            inviteCode: inviteCode,
            displayName: displayName,
            primaryGoal: "",
            on: request.db
        )
    }

    private static func assertRoleAllowed(_ role: UserRole, adminSetupSecret: String?) async throws {
        guard role == .admin else { return }
        let expected = Environment.get("ADMIN_SETUP_SECRET")
        guard let expected, !expected.isEmpty, adminSetupSecret == expected else {
            throw Abort(.forbidden, reason: "Admin registration is restricted")
        }
    }

    private static func validatePassword(_ password: String) throws {
        guard password.count >= 8 else {
            throw Abort(.badRequest, reason: "Password must be at least 8 characters")
        }
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }
}

struct RegisterRequest: Content {
    var email: String
    var password: String
    var role: String
    var displayName: String
    var inviteCode: String?
    var adminSetupSecret: String?
}

struct LoginRequest: Content {
    var email: String
    var password: String
}

struct GoogleSignInRequest: Content {
    var code: String
    var role: String
    var displayName: String?
    var inviteCode: String?
    var redirectURI: String
}

struct AppleSignInRequest: Content {
    var identityToken: String
    var role: String
    var displayName: String?
    var inviteCode: String?
    var adminSetupSecret: String?
}

struct RefreshTokenRequest: Content {
    var refreshToken: String
}

struct ForgotPasswordRequest: Content {
    var email: String
}

struct ResetPasswordRequest: Content {
    var token: String
    var newPassword: String
}

struct PasswordResetRequestedResponse: Content {
    let message: String
    var resetToken: String?
}

struct MessageResponse: Content {
    let message: String
}

private extension Sequence where Element == UInt8 {
    var base64: String { Data(self).base64EncodedString() }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
