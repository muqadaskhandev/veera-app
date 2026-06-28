import Crypto
import Fluent
import Foundation
import JWT
import Vapor

struct AccessTokenPayload: JWTPayload {
    var subject: SubjectClaim
    var role: String
    var expiration: ExpirationClaim

    func verify(using signer: JWTSigner) throws {
        try expiration.verifyNotExpired()
    }
}

enum TokenService {
    private static let accessTokenLifetime: TimeInterval = 60 * 60
    private static let refreshTokenLifetime: TimeInterval = 60 * 60 * 24 * 30

    static func issueTokens(for user: User, on request: Request) async throws -> AuthTokenResponse {
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }

        let accessPayload = AccessTokenPayload(
            subject: SubjectClaim(value: userID.uuidString),
            role: user.role,
            expiration: ExpirationClaim(value: Date().addingTimeInterval(accessTokenLifetime))
        )
        let accessToken = try request.jwt.sign(accessPayload)

        let refreshToken = [UInt8].random(count: 32).base64
        let refreshHash = SHA256.hash(data: Data(refreshToken.utf8)).hex

        let session = AuthSession(
            userID: userID,
            refreshTokenHash: refreshHash,
            expiresAt: Date().addingTimeInterval(refreshTokenLifetime)
        )
        try await session.save(on: request.db)

        return AuthTokenResponse(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: Int(accessTokenLifetime),
            user: try UserDTO(from: user)
        )
    }

    static func refresh(using refreshToken: String, on request: Request) async throws -> AuthTokenResponse {
        let refreshHash = SHA256.hash(data: Data(refreshToken.utf8)).hex
        guard let session = try await AuthSession.query(on: request.db)
            .filter(\.$refreshTokenHash == refreshHash)
            .first(),
            session.isValid else {
            throw Abort(.unauthorized, reason: "Invalid refresh token")
        }

        let user = try await session.$user.get(on: request.db)
        guard user.isActive else {
            throw Abort(.unauthorized, reason: "Invalid refresh token")
        }

        session.revokedAt = Date()
        try await session.save(on: request.db)
        return try await issueTokens(for: user, on: request)
    }

    static func revoke(using refreshToken: String, on request: Request) async throws {
        let refreshHash = SHA256.hash(data: Data(refreshToken.utf8)).hex
        guard let session = try await AuthSession.query(on: request.db)
            .filter(\.$refreshTokenHash == refreshHash)
            .first() else { return }
        session.revokedAt = Date()
        try await session.save(on: request.db)
    }
}

struct AuthTokenResponse: Content {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: UserDTO
}

private extension Sequence where Element == UInt8 {
    var base64: String {
        Data(self).base64EncodedString()
    }
}

private extension SHA256.Digest {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
