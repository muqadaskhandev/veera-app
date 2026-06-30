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
        if let existing = try await User.query(on: request.db).filter(\.$email == normalizedEmail).first() {
            if existing.isEmailVerified {
                throw Abort(.conflict, reason: "Email already registered")
            }
            guard existing.role == role.rawValue else {
                throw Abort(.conflict, reason: "Email already registered")
            }
            guard let passwordHash = existing.passwordHash,
                  try Bcrypt.verify(password, created: passwordHash) else {
                throw Abort(.conflict, reason: "Email already registered")
            }
            let userID = try existing.requireID()
            if try await canIssueVerificationCode(for: userID, on: request.db) {
                let code = try await EmailVerificationService.issueCode(for: existing, on: request.db)
                EmailVerificationService.queueVerificationEmail(to: normalizedEmail, code: code, on: request.application)
            }
            return .pending(email: normalizedEmail)
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
        EmailVerificationService.queueVerificationEmail(to: normalizedEmail, code: code, on: request.application)
        return .pending(email: normalizedEmail)
    }

    static func verifyEmail(code: String, email: String, on request: Request) async throws -> AuthTokenResponse {
        let user = try await EmailVerificationService.verify(code: code, email: email, on: request.db)
        return try await TokenService.issueTokens(for: user, on: request)
    }

    static func resendVerificationEmail(email: String, on request: Request) async throws -> ResendVerificationResponse {
        let normalizedEmail = email.lowercased()
        guard let user = try await User.query(on: request.db).filter(\.$email == normalizedEmail).first() else {
            return ResendVerificationResponse(
                message: "If that email exists, a new code was sent.",
                retryAfterSeconds: nil,
                alreadyVerified: false
            )
        }
        guard !user.isEmailVerified else {
            return ResendVerificationResponse(
                message: "Your email is already verified. Please log in.",
                retryAfterSeconds: nil,
                alreadyVerified: true
            )
        }

        let userID = try user.requireID()
        try await EmailVerificationService.assertResendAllowed(for: userID, on: request.db)

        let code = try await EmailVerificationService.issueCode(for: user, on: request.db)
        EmailVerificationService.queueVerificationEmail(to: normalizedEmail, code: code, on: request.application)
        return ResendVerificationResponse(
            message: "If that email exists, a new code was sent.",
            retryAfterSeconds: Int(EmailVerificationService.resendCooldown),
            alreadyVerified: false
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
            throw Abort(.forbidden, reason: "Please verify your email with the 6-digit code before signing in.")
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
            return PasswordResetRequestedResponse(
                message: "If that email exists, a 6-digit reset code was sent.",
                retryAfterSeconds: nil
            )
        }

        let userID = try user.requireID()
        try await PasswordResetService.assertResendAllowed(for: userID, on: request.db)

        let code = try await PasswordResetService.issueCode(for: user, on: request.db)
        PasswordResetService.queueResetEmail(to: normalizedEmail, code: code, on: request.application)

        return PasswordResetRequestedResponse(
            message: "If that email exists, a 6-digit reset code was sent.",
            retryAfterSeconds: Int(PasswordResetService.resendCooldown)
        )
    }

    static func resetPassword(email: String, code: String, newPassword: String, on request: Request) async throws -> MessageResponse {
        try validatePassword(newPassword)
        _ = try await PasswordResetService.resetPassword(
            email: email,
            code: code,
            newPassword: newPassword,
            on: request.db
        )
        return MessageResponse(message: "Password updated successfully")
    }

    private static func canIssueVerificationCode(for userID: UUID, on database: any Database) async throws -> Bool {
        guard let latest = try await EmailVerificationCode.query(on: database)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .descending)
            .first(),
            let createdAt = latest.createdAt else {
            return true
        }
        return Date().timeIntervalSince(createdAt) >= EmailVerificationService.resendCooldown
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
            return
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
    var email: String
    var code: String
    var newPassword: String
}

struct PasswordResetRequestedResponse: Content {
    let message: String
    let retryAfterSeconds: Int?
}

struct MessageResponse: Content {
    let message: String
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
