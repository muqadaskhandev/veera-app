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

    @Field(key: "client_is_unread")
    var clientIsUnread: Bool

    @Field(key: "last_active_at")
    var lastActiveAt: Date

    @OptionalField(key: "last_message_preview")
    var lastMessagePreview: String?

    @OptionalField(key: "last_message_at")
    var lastMessageAt: Date?

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
        clientIsUnread: Bool = false,
        lastActiveAt: Date = .now
    ) {
        self.id = id
        self.$trainer.id = trainerID
        self.$client.id = clientID
        self.clientName = clientName
        self.initials = initials
        self.isUnread = isUnread
        self.clientIsUnread = clientIsUnread
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
    let lastMessagePreview: String?
    let lastMessageAt: Date?
    let otherParticipantUserID: UUID?
    let otherParticipantIsOnline: Bool
    let otherParticipantLastSeen: Date?

    init(
        id: UUID,
        trainerID: UUID,
        clientID: UUID,
        clientName: String,
        initials: String,
        isUnread: Bool,
        lastActiveAt: Date,
        lastMessagePreview: String?,
        lastMessageAt: Date?,
        otherParticipantUserID: UUID? = nil,
        otherParticipantIsOnline: Bool = false,
        otherParticipantLastSeen: Date? = nil
    ) {
        self.id = id
        self.trainerID = trainerID
        self.clientID = clientID
        self.clientName = clientName
        self.initials = initials
        self.isUnread = isUnread
        self.lastActiveAt = lastActiveAt
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageAt = lastMessageAt
        self.otherParticipantUserID = otherParticipantUserID
        self.otherParticipantIsOnline = otherParticipantIsOnline
        self.otherParticipantLastSeen = otherParticipantLastSeen
    }

    init(from conversation: Conversation, viewerRole: UserRole) throws {
        guard let id = conversation.id else {
            throw Abort(.internalServerError, reason: "Conversation missing id")
        }
        self.init(
            id: id,
            trainerID: conversation.$trainer.id,
            clientID: conversation.$client.id,
            clientName: conversation.clientName,
            initials: conversation.initials,
            isUnread: viewerRole == .client ? conversation.clientIsUnread : conversation.isUnread,
            lastActiveAt: conversation.lastActiveAt,
            lastMessagePreview: conversation.lastMessagePreview,
            lastMessageAt: conversation.lastMessageAt
        )
    }

    static func make(
        from conversation: Conversation,
        viewer: User,
        on database: any Database
    ) async throws -> ConversationDTO {
        let role = viewer.userRole ?? .client
        var dto = try ConversationDTO(from: conversation, viewerRole: role)
        let viewerID = try viewer.requireID()
        guard let otherID = try await PresenceService.otherParticipantUserID(
            in: conversation,
            viewerID: viewerID,
            on: database
        ) else {
            return dto
        }
        let presence = await PresenceService.state(for: otherID, on: database)
        dto = ConversationDTO(
            id: dto.id,
            trainerID: dto.trainerID,
            clientID: dto.clientID,
            clientName: dto.clientName,
            initials: dto.initials,
            isUnread: dto.isUnread,
            lastActiveAt: dto.lastActiveAt,
            lastMessagePreview: dto.lastMessagePreview,
            lastMessageAt: dto.lastMessageAt,
            otherParticipantUserID: otherID,
            otherParticipantIsOnline: presence.isOnline,
            otherParticipantLastSeen: presence.lastSeen
        )
        return dto
    }
}

struct ConversationDetailResponse: Content {
    let conversation: ConversationDTO
    let messages: [MessageDTO]
}
