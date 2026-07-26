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

    /// Per-viewer inbox flags — archive/delete do not affect the other participant.
    @Field(key: "trainer_is_archived")
    var trainerIsArchived: Bool

    @Field(key: "client_is_archived")
    var clientIsArchived: Bool

    @Field(key: "trainer_is_deleted")
    var trainerIsDeleted: Bool

    @Field(key: "client_is_deleted")
    var clientIsDeleted: Bool

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
        lastActiveAt: Date = .now,
        trainerIsArchived: Bool = false,
        clientIsArchived: Bool = false,
        trainerIsDeleted: Bool = false,
        clientIsDeleted: Bool = false
    ) {
        self.id = id
        self.$trainer.id = trainerID
        self.$client.id = clientID
        self.clientName = clientName
        self.initials = initials
        self.isUnread = isUnread
        self.clientIsUnread = clientIsUnread
        self.lastActiveAt = lastActiveAt
        self.trainerIsArchived = trainerIsArchived
        self.clientIsArchived = clientIsArchived
        self.trainerIsDeleted = trainerIsDeleted
        self.clientIsDeleted = clientIsDeleted
    }

    func isArchived(for role: UserRole) -> Bool {
        role == .client ? clientIsArchived : trainerIsArchived
    }

    func isDeleted(for role: UserRole) -> Bool {
        role == .client ? clientIsDeleted : trainerIsDeleted
    }

    func setArchived(_ archived: Bool, for role: UserRole) {
        if role == .client {
            clientIsArchived = archived
        } else {
            trainerIsArchived = archived
        }
    }

    func setDeleted(_ deleted: Bool, for role: UserRole) {
        if role == .client {
            clientIsDeleted = deleted
            if deleted { clientIsArchived = false }
        } else {
            trainerIsDeleted = deleted
            if deleted { trainerIsArchived = false }
        }
    }

    /// Clears hide flags when the viewer re-opens or sends in the thread.
    func restoreVisibility(for role: UserRole) {
        setDeleted(false, for: role)
        setArchived(false, for: role)
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
    let isArchived: Bool
    let lastActiveAt: Date
    let lastMessagePreview: String?
    let lastMessageAt: Date?
    let otherParticipantUserID: UUID?
    let otherParticipantIsOnline: Bool
    let otherParticipantLastSeen: Date?
    let otherParticipantAvatarURL: String?

    init(
        id: UUID,
        trainerID: UUID,
        clientID: UUID,
        clientName: String,
        initials: String,
        isUnread: Bool,
        isArchived: Bool = false,
        lastActiveAt: Date,
        lastMessagePreview: String?,
        lastMessageAt: Date?,
        otherParticipantUserID: UUID? = nil,
        otherParticipantIsOnline: Bool = false,
        otherParticipantLastSeen: Date? = nil,
        otherParticipantAvatarURL: String? = nil
    ) {
        self.id = id
        self.trainerID = trainerID
        self.clientID = clientID
        self.clientName = clientName
        self.initials = initials
        self.isUnread = isUnread
        self.isArchived = isArchived
        self.lastActiveAt = lastActiveAt
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageAt = lastMessageAt
        self.otherParticipantUserID = otherParticipantUserID
        self.otherParticipantIsOnline = otherParticipantIsOnline
        self.otherParticipantLastSeen = otherParticipantLastSeen
        self.otherParticipantAvatarURL = otherParticipantAvatarURL
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
            isArchived: conversation.isArchived(for: viewerRole),
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
        let avatarURL = try await ProfileService.avatarURL(forUserID: otherID, on: database)
        dto = ConversationDTO(
            id: dto.id,
            trainerID: dto.trainerID,
            clientID: dto.clientID,
            clientName: dto.clientName,
            initials: dto.initials,
            isUnread: dto.isUnread,
            isArchived: dto.isArchived,
            lastActiveAt: dto.lastActiveAt,
            lastMessagePreview: dto.lastMessagePreview,
            lastMessageAt: dto.lastMessageAt,
            otherParticipantUserID: otherID,
            otherParticipantIsOnline: presence.isOnline,
            otherParticipantLastSeen: presence.lastSeen,
            otherParticipantAvatarURL: avatarURL
        )
        return dto
    }
}

struct UpdateConversationArchiveRequest: Content {
    let archived: Bool
}

struct ConversationDetailResponse: Content {
    let conversation: ConversationDTO
    let messages: [MessageDTO]
}
