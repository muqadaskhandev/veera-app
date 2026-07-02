import Fluent
import Vapor

final class User: Model, Content, Authenticatable, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @OptionalField(key: "email")
    var email: String?

    @OptionalField(key: "password_hash")
    var passwordHash: String?

    @Field(key: "role")
    var role: String

    @OptionalField(key: "apple_subject")
    var appleSubject: String?

    @OptionalField(key: "google_subject")
    var googleSubject: String?

    @Field(key: "display_name")
    var displayName: String

    @OptionalField(key: "avatar_path")
    var avatarPath: String?

    @Field(key: "is_email_verified")
    var isEmailVerified: Bool

    @Field(key: "is_active")
    var isActive: Bool

    @OptionalField(key: "last_seen_at")
    var lastSeenAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        email: String?,
        passwordHash: String?,
        role: UserRole,
        appleSubject: String? = nil,
        googleSubject: String? = nil,
        displayName: String,
        isEmailVerified: Bool = false,
        isActive: Bool = true
    ) {
        self.id = id
        self.email = email?.lowercased()
        self.passwordHash = passwordHash
        self.role = role.rawValue
        self.appleSubject = appleSubject
        self.googleSubject = googleSubject
        self.displayName = displayName
        self.isEmailVerified = isEmailVerified
        self.isActive = isActive
    }

    var userRole: UserRole? {
        UserRole(rawValue: role)
    }
}

struct UserDTO: Content {
    let id: UUID
    let email: String?
    let role: String
    let displayName: String
    let isEmailVerified: Bool
    let createdAt: Date?

    init(from user: User) throws {
        guard let id = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }
        self.id = id
        self.email = user.email
        self.role = user.role
        self.displayName = user.displayName
        self.isEmailVerified = user.isEmailVerified
        self.createdAt = user.createdAt
    }
}
