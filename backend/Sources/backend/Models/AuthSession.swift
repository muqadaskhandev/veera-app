import Fluent
import Vapor

final class AuthSession: Model, @unchecked Sendable {
    static let schema = "auth_sessions"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "refresh_token_hash")
    var refreshTokenHash: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "revoked_at")
    var revokedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(userID: UUID, refreshTokenHash: String, expiresAt: Date) {
        self.$user.id = userID
        self.refreshTokenHash = refreshTokenHash
        self.expiresAt = expiresAt
    }

    var isValid: Bool {
        revokedAt == nil && expiresAt > Date()
    }
}
