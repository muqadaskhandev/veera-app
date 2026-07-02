import Fluent
import Vapor

final class Message: Model, @unchecked Sendable {
    static let schema = "messages"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "conversation_id")
    var conversation: Conversation

    @OptionalParent(key: "sender_user_id")
    var senderUser: User?

    @Field(key: "kind")
    var kind: String

    @Field(key: "body")
    var body: String

    @Field(key: "is_outgoing")
    var isOutgoing: Bool

    @OptionalField(key: "reaction")
    var reaction: String?

    @OptionalField(key: "attachment_url")
    var attachmentURL: String?

    @Field(key: "status")
    var status: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        conversationID: UUID,
        senderUserID: UUID?,
        kind: String,
        body: String,
        isOutgoing: Bool,
        reaction: String? = nil,
        attachmentURL: String? = nil,
        status: String = "sent"
    ) {
        self.id = id
        self.$conversation.id = conversationID
        if let senderUserID {
            self.$senderUser.id = senderUserID
        }
        self.kind = kind
        self.body = body
        self.isOutgoing = isOutgoing
        self.reaction = reaction
        self.attachmentURL = attachmentURL
        self.status = status
    }
}

extension Message: Content {}

struct MessageDTO: Content {
    let id: UUID
    let conversationID: UUID
    let senderUserID: UUID?
    let kind: String
    let body: String
    let isOutgoing: Bool
    let reaction: String?
    let attachmentURL: String?
    let status: String
    let createdAt: Date?

    init(from message: Message, viewerUserID: UUID) throws {
        guard let id = message.id else {
            throw Abort(.internalServerError, reason: "Message missing id")
        }
        self.id = id
        self.conversationID = message.$conversation.id
        self.senderUserID = message.$senderUser.id
        self.kind = message.kind
        self.body = message.body
        self.isOutgoing = message.$senderUser.id == viewerUserID
        self.reaction = message.reaction
        self.attachmentURL = message.attachmentURL
        self.status = message.status
        self.createdAt = message.createdAt
    }
}

struct CreateMessageRequest: Content {
    var kind: String
    var body: String
    var attachmentURL: String?
}

struct UpdateMessageReactionRequest: Content {
    var reaction: String?
}

struct MessagesPageResponse: Content {
    let messages: [MessageDTO]
    let hasMore: Bool
}
