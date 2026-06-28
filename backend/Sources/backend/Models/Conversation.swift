import Fluent
import Vapor

final class Conversation: Model, @unchecked Sendable {
    static let schema = "conversations"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "trainer_id")
    var trainer: Trainer

    @Parent(key: "client_id")
    var client: Client

    @Field(key: "client_name")
    var clientName: String

    @Field(key: "initials")
    var initials: String

    @Field(key: "is_unread")
    var isUnread: Bool

    @Field(key: "last_active_at")
    var lastActiveAt: Date

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Children(for: \.$conversation)
    var messages: [Message]

    init() {}

    init(
        id: UUID? = nil,
        trainerID: UUID,
        clientID: UUID,
        clientName: String,
        initials: String,
        isUnread: Bool = false,
        lastActiveAt: Date = .now
    ) {
        self.id = id
        self.$trainer.id = trainerID
        self.$client.id = clientID
        self.clientName = clientName
        self.initials = initials
        self.isUnread = isUnread
        self.lastActiveAt = lastActiveAt
    }
}

extension Conversation: Content {}

struct ConversationDTO: Content {
    let id: UUID
    let trainerID: UUID
    let clientID: UUID
    let clientName: String
    let initials: String
    let isUnread: Bool
    let lastActiveAt: Date

    init(from conversation: Conversation) throws {
        guard let id = conversation.id else {
            throw Abort(.internalServerError, reason: "Conversation missing id")
        }
        self.id = id
        self.trainerID = conversation.$trainer.id
        self.clientID = conversation.$client.id
        self.clientName = conversation.clientName
        self.initials = conversation.initials
        self.isUnread = conversation.isUnread
        self.lastActiveAt = conversation.lastActiveAt
    }
}
