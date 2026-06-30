import Crypto
import Fluent
import Vapor

enum EmailVerificationService {
  static let codeLifetime: TimeInterval = 60 * 10
  static let resendCooldown: TimeInterval = 60

  static func assertResendAllowed(for userID: UUID, on database: any Database) async throws {
    guard let latest = try await EmailVerificationCode.query(on: database)
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
      let existing = try await EmailVerificationCode.query(on: database)
        .filter(\.$user.$id == userID)
        .all()
      for item in existing where item.isValid {
        item.usedAt = Date()
        try await item.save(on: database)
      }

      let record = EmailVerificationCode(
        userID: userID,
        codeHash: codeHash,
        expiresAt: Date().addingTimeInterval(codeLifetime)
      )
      try await record.save(on: database)
    }

    return code
  }

  static func sendVerificationCode(to email: String, code: String, on request: Request) async throws {
    try await sendVerificationCode(to: email, code: code, on: request.application)
  }

  static func sendVerificationCode(to email: String, code: String, on app: Application) async throws {
    if SESEmailService.isConfigured() {
      let template = EmailTemplateService.verificationEmail(code: code)
      try await SESEmailService.send(
        to: email,
        subject: template.subject,
        textBody: template.text,
        htmlBody: template.html,
        on: app
      )
    } else if app.environment == .development {
      TransactionalEmailService.queueVerification(to: email, code: code, on: app)
    } else {
      throw Abort(.internalServerError, reason: "Email service is not configured")
    }
  }

  static func queueVerificationEmail(to email: String, code: String, on app: Application) {
    TransactionalEmailService.queueVerification(to: email, code: code, on: app)
  }

  static func verify(code: String, email: String, on database: any Database) async throws -> User {
    let normalizedEmail = email.lowercased()
    guard let user = try await User.query(on: database).filter(\.$email == normalizedEmail).first() else {
      throw Abort(.badRequest, reason: "Invalid verification code")
    }
    guard user.isActive else {
      throw Abort(.forbidden, reason: "Account is inactive")
    }

    let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
    let codeHash = SHA256.hash(data: Data(normalizedCode.utf8)).hex

    if user.isEmailVerified {
      if try await EmailVerificationCode.query(on: database)
        .filter(\.$user.$id == user.id!)
        .filter(\.$codeHash == codeHash)
        .first() != nil {
        return user
      }
      throw Abort(.badRequest, reason: "Email already verified. Please log in.")
    }

    guard let record = try await EmailVerificationCode.query(on: database)
      .filter(\.$user.$id == user.id!)
      .filter(\.$codeHash == codeHash)
      .sort(\.$createdAt, .descending)
      .first(),
      record.isValid else {
      throw Abort(.badRequest, reason: "Invalid or expired verification code")
    }

    record.usedAt = Date()
    user.isEmailVerified = true
    try await record.save(on: database)
    try await user.save(on: database)
    return user
  }
}

private extension SHA256.Digest {
  var hex: String { map { String(format: "%02x", $0) }.joined() }
}

struct RegisterResponse: Content {
  let requiresEmailVerification: Bool
  let email: String
  let message: String
  let devCode: String?
  let accessToken: String?
  let refreshToken: String?
  let expiresIn: Int?
  let user: UserDTO?

  static func pending(email: String) -> RegisterResponse {
    RegisterResponse(
      requiresEmailVerification: true,
      email: email,
      message: "We sent a 6-digit code to your email.",
      devCode: nil,
      accessToken: nil,
      refreshToken: nil,
      expiresIn: nil,
      user: nil
    )
  }

  static func completed(_ auth: AuthTokenResponse) -> RegisterResponse {
    RegisterResponse(
      requiresEmailVerification: false,
      email: auth.user.email ?? "",
      message: "Registration complete",
      devCode: nil,
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
      expiresIn: auth.expiresIn,
      user: auth.user
    )
  }
}

struct VerifyEmailRequest: Content {
  var email: String
  var code: String
}

struct ResendVerificationRequest: Content {
  var email: String
}

struct ResendVerificationResponse: Content {
  let message: String
  let retryAfterSeconds: Int?
  let alreadyVerified: Bool
}
