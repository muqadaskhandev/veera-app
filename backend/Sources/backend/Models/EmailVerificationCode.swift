import Fluent
import Vapor

final class EmailVerificationCode: Model, @unchecked Sendable {
    static let schema = "email_verification_codes"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "code_hash")
    var codeHash: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "used_at")
    var usedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(userID: UUID, codeHash: String, expiresAt: Date) {
        self.$user.id = userID
        self.codeHash = codeHash
        self.expiresAt = expiresAt
    }

    var isValid: Bool {
        usedAt == nil && expiresAt > Date()
    }
}
