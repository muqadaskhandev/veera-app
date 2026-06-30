import Fluent
import Vapor

final class OuraToken: Model, @unchecked Sendable {
    static let schema = "oura_tokens"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "access_token")
    var accessToken: String

    @Field(key: "refresh_token")
    var refreshToken: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @Field(key: "scope")
    var scope: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        scope: String
    ) {
        self.id = id
        self.$user.id = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }
}
