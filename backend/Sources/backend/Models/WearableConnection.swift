import Fluent
import Vapor

final class WearableConnection: Model, @unchecked Sendable {
    static let schema = "wearable_connections"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "provider")
    var provider: String

    @Field(key: "connected_at")
    var connectedAt: Date

    @OptionalField(key: "last_synced_at")
    var lastSyncedAt: Date?

    init() {}

    init(id: UUID? = nil, userID: UUID, provider: String, connectedAt: Date = Date(), lastSyncedAt: Date? = nil) {
        self.id = id
        self.$user.id = userID
        self.provider = provider
        self.connectedAt = connectedAt
        self.lastSyncedAt = lastSyncedAt
    }
}

struct WearableConnectionDTO: Content {
    let provider: String
    let connectedAt: Date
    let lastSyncedAt: Date?

    init(from connection: WearableConnection) {
        self.provider = connection.provider
        self.connectedAt = connection.connectedAt
        self.lastSyncedAt = connection.lastSyncedAt
    }
}
