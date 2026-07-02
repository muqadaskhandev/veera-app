import Fluent
import Vapor

final class PushDeviceToken: Model, @unchecked Sendable {
    static let schema = "push_device_tokens"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "token")
    var token: String

    @Field(key: "platform")
    var platform: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(userID: UUID, token: String, platform: String = "ios") {
        self.$user.id = userID
        self.token = token
        self.platform = platform
    }
}

struct RegisterPushTokenRequest: Content {
    var token: String
    var platform: String?
}
