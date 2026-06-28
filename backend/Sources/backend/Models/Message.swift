import Fluent
import Vapor

final class Message: Model, @unchecked Sendable {
    static let schema = "messages"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "conversation_id")
    var conversation: Conversation

    @Field(key: "kind")
    var kind: String

    @Field(key: "body")
    var body: String

    @Field(key: "is_outgoing")
    var isOutgoing: Bool

    @OptionalField(key: "reaction")
    var reaction: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        conversationID: UUID,
        kind: String,
        body: String,
        isOutgoing: Bool,
        reaction: String? = nil
    ) {
        self.id = id
        self.$conversation.id = conversationID
        self.kind = kind
        self.body = body
        self.isOutgoing = isOutgoing
        self.reaction = reaction
    }
}

extension Message: Content {}

struct MessageDTO: Content {
    let id: UUID
    let conversationID: UUID
    let kind: String
    let body: String
    let isOutgoing: Bool
    let reaction: String?
    let createdAt: Date?

    init(from message: Message) throws {
        guard let id = message.id else {
            throw Abort(.internalServerError, reason: "Message missing id")
        }
        self.id = id
        self.conversationID = message.$conversation.id
        self.kind = message.kind
        self.body = message.body
        self.isOutgoing = message.isOutgoing
        self.reaction = message.reaction
        self.createdAt = message.createdAt
    }
}

struct CreateMessageRequest: Content {
    var kind: String
    var body: String
    var isOutgoing: Bool
}
