import Fluent
import Vapor

final class OuraOAuthState: Model, @unchecked Sendable {
    static let schema = "oura_oauth_states"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "state")
    var state: String

    @Field(key: "expires_at")
    var expiresAt: Date

    init() {}

    init(id: UUID? = nil, userID: UUID, state: String, expiresAt: Date) {
        self.id = id
        self.$user.id = userID
        self.state = state
        self.expiresAt = expiresAt
    }
}

struct OuraAuthorizeResponse: Content {
    let authorizationURL: String
    let state: String
    let redirectURI: String
}

struct OuraCallbackRequest: Content {
    let code: String
    let state: String
}

struct OuraStatusResponse: Content {
    let configured: Bool
    let devMode: Bool
}
