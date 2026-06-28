import Foundation
import JWTKit
import Vapor

struct AppleIdentityClaims: JWTPayload {
    var subject: SubjectClaim
    var email: String?
    var emailVerified: Bool?
    var issuer: IssuerClaim
    var audience: AudienceClaim
    var expiration: ExpirationClaim

    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case email
        case emailVerified = "email_verified"
        case issuer = "iss"
        case audience = "aud"
        case expiration = "exp"
    }

    func verify(using signer: JWTSigner) throws {
        try expiration.verifyNotExpired()
        guard issuer.value == "https://appleid.apple.com" else {
            throw Abort(.unauthorized, reason: "Invalid Apple token issuer")
        }
    }
}

enum AppleAuthService {
    private static let jwksURL = "https://appleid.apple.com/auth/keys"

    static func verify(identityToken: String, on app: Application) async throws -> AppleIdentityClaims {
        let clientID = Environment.get("APPLE_CLIENT_ID") ?? "app.rork.hiyjy25oz4yjrbssyotkw"
        let signers = try await appleSigners(on: app)
        let payload = try signers.verify(identityToken, as: AppleIdentityClaims.self)

        guard payload.audience.value.contains(clientID) else {
            throw Abort(.unauthorized, reason: "Apple token audience mismatch")
        }

        return payload
    }

    private static func appleSigners(on app: Application) async throws -> JWTSigners {
        let response = try await app.client.get(URI(string: jwksURL))
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Unable to load Apple public keys")
        }

        struct JWKSResponse: Decodable {
            let keys: [JWK]
        }

        let jwks = try response.content.decode(JWKSResponse.self)
        let signers = JWTSigners()
        for key in jwks.keys {
            try signers.use(jwk: key)
        }
        return signers
    }
}
