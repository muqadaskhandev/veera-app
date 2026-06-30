import Fluent
import Vapor

final class Profile: Model, Content, @unchecked Sendable {
    static let schema = "profiles"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "display_name")
    var displayName: String

    @Field(key: "title")
    var title: String

    @Field(key: "bio")
    var bio: String

    @Field(key: "specialties_json")
    var specialtiesJSON: String

    @OptionalField(key: "avatar_path")
    var avatarPath: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        displayName: String,
        title: String = "",
        bio: String = "",
        specialtiesJSON: String = "[]",
        avatarPath: String? = nil
    ) {
        self.id = id
        self.$user.id = userID
        self.displayName = displayName
        self.title = title
        self.bio = bio
        self.specialtiesJSON = specialtiesJSON
        self.avatarPath = avatarPath
    }
}

struct ProfileDetailsDTO: Content {
    let displayName: String
    let title: String
    let bio: String
    let specialties: [String]
    let avatarURL: String?

    init(from profile: Profile) {
        self.displayName = profile.displayName
        self.title = profile.title
        self.bio = profile.bio
        self.specialties = TrainerSpecialties.decode(profile.specialtiesJSON)
        self.avatarURL = AvatarService.publicURL(
            for: profile.avatarPath,
            cacheVersion: profile.updatedAt.map { String(Int($0.timeIntervalSince1970)) }
        )
    }
}
