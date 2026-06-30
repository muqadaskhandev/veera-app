import Crypto
import Fluent
import Vapor

enum PasswordResetService {
    static let codeLifetime: TimeInterval = 60 * 10
    static let resendCooldown: TimeInterval = 60

    static func assertResendAllowed(for userID: UUID, on database: any Database) async throws {
        guard let latest = try await PasswordResetToken.query(on: database)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .descending)
            .first(),
            let createdAt = latest.createdAt else {
            return
        }
        let elapsed = Date().timeIntervalSince(createdAt)
        guard elapsed < resendCooldown else { return }
        let retry = Int(ceil(resendCooldown - elapsed))
        throw Abort(.tooManyRequests, reason: "Please wait \(retry) seconds before requesting a new code.")
    }

    static func issueCode(for user: User, on database: any Database) async throws -> String {
        let code = String(format: "%06d", Int.random(in: 0...999_999))
        let codeHash = SHA256.hash(data: Data(code.utf8)).hex

        if let userID = user.id {
            let existing = try await PasswordResetToken.query(on: database)
                .filter(\.$user.$id == userID)
                .all()
            for item in existing where item.isValid {
                item.usedAt = Date()
                try await item.save(on: database)
            }

            let record = PasswordResetToken(
                userID: userID,
                tokenHash: codeHash,
                expiresAt: Date().addingTimeInterval(codeLifetime)
            )
            try await record.save(on: database)
        }

        return code
    }

    static func sendResetCode(to email: String, code: String, on app: Application) async throws {
        let subject = "Your Verra password reset code"
        let textBody = """
        Your Verra password reset code is: \(code)

        This code expires in 10 minutes.
        If you did not request this, you can ignore this email.
        """
        let htmlBody = """
        <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#111;">
          <p>Your Verra password reset code is:</p>
          <p style="font-size:32px;font-weight:700;letter-spacing:6px;margin:16px 0;">\(code)</p>
          <p style="color:#555;">This code expires in 10 minutes.</p>
          <p style="color:#555;">If you did not request this, you can ignore this email.</p>
        </div>
        """

        try await SESEmailService.send(
            to: email,
            subject: subject,
            textBody: textBody,
            htmlBody: htmlBody,
            on: app
        )
    }

    static func queueResetEmail(to email: String, code: String, on app: Application) {
        Task {
            do {
                try await sendResetCode(to: email, code: code, on: app)
            } catch {
                app.logger.error("Password reset email delivery failed: \(error)")
            }
        }
    }

    static func resetPassword(
        email: String,
        code: String,
        newPassword: String,
        on database: any Database
    ) async throws -> User {
        let normalizedEmail = email.lowercased()
        guard let user = try await User.query(on: database).filter(\.$email == normalizedEmail).first() else {
            throw Abort(.badRequest, reason: "Invalid or expired reset code")
        }
        guard user.isActive else {
            throw Abort(.forbidden, reason: "Account is inactive")
        }

        let codeHash = SHA256.hash(data: Data(code.utf8)).hex
        guard let record = try await PasswordResetToken.query(on: database)
            .filter(\.$user.$id == user.id!)
            .filter(\.$tokenHash == codeHash)
            .sort(\.$createdAt, .descending)
            .first(),
            record.isValid else {
            throw Abort(.badRequest, reason: "Invalid or expired reset code")
        }

        record.usedAt = Date()
        user.passwordHash = try Bcrypt.hash(newPassword)
        try await record.save(on: database)
        try await user.save(on: database)
        return user
    }
}
