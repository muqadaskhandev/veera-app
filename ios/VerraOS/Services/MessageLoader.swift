import Foundation

struct ConversationDTO: Codable {
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
}

struct MessageDTO: Codable {
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
}

struct ConversationDetailResponse: Codable {
    let conversation: ConversationDTO
    let messages: [MessageDTO]
}

struct MessagesPageResponse: Codable {
    let messages: [MessageDTO]
    let hasMore: Bool
}

struct ChatEventDTO: Codable {
    let type: String
    let message: MessageDTO?
    let conversationID: UUID?
    let messageID: UUID?
    let reaction: String?
    let userID: UUID?
    let isTyping: Bool?
    let preview: String?
    let isOnline: Bool?
    let lastSeen: Date?
    let presence: [PresenceStateDTO]?
}

struct PresenceStateDTO: Codable {
    let userID: UUID
    let isOnline: Bool
    let lastSeen: Date?
}

struct AttachmentUploadResponse: Codable {
    let attachmentURL: String
}

enum MessageLoader {
    static func conversation(from dto: ConversationDTO, messages: [Message] = []) -> Conversation {
        Conversation(
            id: dto.id,
            clientID: dto.clientID,
            clientName: dto.clientName,
            initials: dto.initials,
            messages: messages,
            isUnread: dto.isUnread,
            lastActiveAt: dto.lastActiveAt,
            lastMessagePreview: dto.lastMessagePreview,
            lastMessageAt: dto.lastMessageAt,
            otherParticipantUserID: dto.otherParticipantUserID,
            otherParticipantIsOnline: dto.otherParticipantIsOnline,
            otherParticipantLastSeen: dto.otherParticipantLastSeen
        )
    }

    static func message(from dto: MessageDTO) -> Message {
        Message(
            id: dto.id,
            kind: kind(from: dto.kind, body: dto.body),
            isOutgoing: dto.isOutgoing,
            sentAt: dto.createdAt ?? .now,
            reaction: dto.reaction.flatMap { Reaction(rawValue: $0) },
            attachmentURL: dto.attachmentURL
        )
    }

    static func kindString(from kind: MessageKind) -> String {
        switch kind {
        case .text: return "text"
        case .photo: return "photo"
        case .video: return "video"
        case .voice: return "voice"
        }
    }

    static func bodyString(from kind: MessageKind) -> String {
        switch kind {
        case .text(let body): return body
        case .photo: return "Photo"
        case .video: return "Video message"
        case .voice(let seconds): return "\(seconds)"
        }
    }

    private static func kind(from raw: String, body: String) -> MessageKind {
        switch raw {
        case "photo": return .photo
        case "video": return .video
        case "voice":
            let seconds = Int(body) ?? 0
            return .voice(seconds: max(1, seconds))
        default: return .text(body)
        }
    }
}

struct PendingChatMessage: Codable, Identifiable {
    let id: UUID
    let conversationID: UUID
    let kind: String
    let body: String
    let attachmentURL: String?

    init(conversationID: UUID, kind: MessageKind, attachmentURL: String? = nil) {
        self.id = UUID()
        self.conversationID = conversationID
        self.kind = MessageLoader.kindString(from: kind)
        self.body = MessageLoader.bodyString(from: kind)
        self.attachmentURL = attachmentURL
    }
}

enum ChatOfflineQueue {
    private static let key = "verra.chat.offlineQueue"

    static func load() -> [PendingChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([PendingChatMessage].self, from: data) else {
            return []
        }
        return items
    }

    static func save(_ items: [PendingChatMessage]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func enqueue(_ item: PendingChatMessage) {
        var items = load()
        items.append(item)
        save(items)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
