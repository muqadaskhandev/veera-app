import Foundation
import Vapor

struct GoogleTokenResponse: Decodable {
    let idToken: String
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
    }
}

struct GoogleTokenInfo: Decodable {
    let sub: String
    let email: String?
    let emailVerified: String?

    enum CodingKeys: String, CodingKey {
        case sub
        case email
        case emailVerified = "email_verified"
    }

    var isEmailVerified: Bool {
        emailVerified == "true"
    }
}

enum GoogleAuthService {
    private struct TokenExchangeForm: Content {
        let code: String
        let client_id: String
        let client_secret: String
        let redirect_uri: String
        let grant_type: String
    }

    static func exchangeAndVerify(code: String, redirectURI: String, on app: Application) async throws -> GoogleTokenInfo {
        let clientID = Environment.get("GOOGLE_CLIENT_ID")
        let clientSecret = Environment.get("GOOGLE_CLIENT_SECRET")
        guard let clientID, let clientSecret, !clientID.isEmpty, !clientSecret.isEmpty else {
            throw Abort(.internalServerError, reason: "Google OAuth is not configured on the server")
        }

        let tokenResponse = try await app.client.post(URI(string: "https://oauth2.googleapis.com/token")) { req in
            req.headers.contentType = .urlEncodedForm
            try req.content.encode(TokenExchangeForm(
                code: code,
                client_id: clientID,
                client_secret: clientSecret,
                redirect_uri: redirectURI,
                grant_type: "authorization_code"
            ))
        }

        guard tokenResponse.status == HTTPStatus.ok else {
            throw Abort(.unauthorized, reason: "Google token exchange failed")
        }

        let tokens = try tokenResponse.content.decode(GoogleTokenResponse.self)

        let infoResponse = try await app.client.get(URI(string: "https://oauth2.googleapis.com/tokeninfo?id_token=\(tokens.idToken)"))
        guard infoResponse.status == HTTPStatus.ok else {
            throw Abort(.unauthorized, reason: "Invalid Google identity token")
        }

        let info = try infoResponse.content.decode(GoogleTokenInfo.self)
        guard info.sub.isEmpty == false else {
            throw Abort(.unauthorized, reason: "Invalid Google account")
        }

        return info
    }
}
