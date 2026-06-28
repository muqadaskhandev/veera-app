import Crypto
import Fluent
import Vapor

enum EmailVerificationService {
  private static let codeLifetime: TimeInterval = 60 * 15

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
    let subject = "Your Verra verification code"
    let textBody = """
    Your Verra verification code is: \(code)

    This code expires in 15 minutes.
    If you did not request this, you can ignore this email.
    """
    let htmlBody = """
    <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#111;">
      <p>Your Verra verification code is:</p>
      <p style="font-size:32px;font-weight:700;letter-spacing:6px;margin:16px 0;">\(code)</p>
      <p style="color:#555;">This code expires in 15 minutes.</p>
      <p style="color:#555;">If you did not request this, you can ignore this email.</p>
    </div>
    """

    try await SESEmailService.send(
      to: email,
      subject: subject,
      textBody: textBody,
      htmlBody: htmlBody,
      on: request
    )
  }

  static func verify(code: String, email: String, on database: any Database) async throws -> User {
    let normalizedEmail = email.lowercased()
    guard let user = try await User.query(on: database).filter(\.$email == normalizedEmail).first() else {
      throw Abort(.badRequest, reason: "Invalid verification code")
    }
    guard user.isActive else {
      throw Abort(.forbidden, reason: "Account is inactive")
    }

    let codeHash = SHA256.hash(data: Data(code.utf8)).hex
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

  static func pending(email: String, devCode: String?) -> RegisterResponse {
    RegisterResponse(
      requiresEmailVerification: true,
      email: email,
      message: "We sent a 6-digit code to your email.",
      devCode: devCode,
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
  let devCode: String?
}
