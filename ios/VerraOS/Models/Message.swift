//
//  Message.swift
//  VerraOS
//

import SwiftUI

/// Tap-back reaction emojis available on a long-press of any bubble.
enum Reaction: String, CaseIterable, Identifiable {
    case heart = "❤️"
    case laugh = "😂"
    case wow = "😮"
    case sad = "😢"
    case angry = "😡"
    case thumbsUp = "👍"

    var id: String { rawValue }
}

/// The kind of content a message carries. Drives the bubble rendering.
enum MessageKind: Hashable {
    case text(String)
    case photo
    case video
    case voice(seconds: Int)

    /// Inbox preview text for the conversation list.
    var preview: String {
        switch self {
        case .text(let body): return body
        case .photo: return "📷 Photo"
        case .video: return "🎥 Video message"
        case .voice: return "🎤 Voice message"
        }
    }
}

/// A single message in a thread.
struct Message: Identifiable, Hashable {
    let id: UUID
    var kind: MessageKind
    /// True when the current user sent it — renders on the right.
    var isOutgoing: Bool
    var sentAt: Date
    var reaction: Reaction?
    var attachmentURL: String?

    var minutesAgo: Int {
        max(0, Int(Date().timeIntervalSince(sentAt) / 60))
    }

    init(
        id: UUID = UUID(),
        kind: MessageKind,
        isOutgoing: Bool,
        sentAt: Date = .now,
        reaction: Reaction? = nil,
        attachmentURL: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.isOutgoing = isOutgoing
        self.sentAt = sentAt
        self.reaction = reaction
        self.attachmentURL = attachmentURL
    }
}

/// A conversation thread tied to a client on the roster.
struct Conversation: Identifiable, Hashable {
    let id: UUID
    /// Links back to the `Client` in `ClientStore`.
    let clientID: UUID
    let clientName: String
    let initials: String
    var messages: [Message]
    var isUnread: Bool
    var lastActiveAt: Date
    var lastMessagePreview: String?
    var lastMessageAt: Date?
    var otherParticipantUserID: UUID?
    var otherParticipantIsOnline: Bool
    var otherParticipantLastSeen: Date?

    /// Presence label for the chat header.
    var presenceLabel: String {
        if otherParticipantIsOnline { return "Active now" }
        if let lastSeen = otherParticipantLastSeen {
            let minutes = max(0, Int(Date().timeIntervalSince(lastSeen) / 60))
            if minutes < 1 { return "Active recently" }
            return "Last seen \(relativeTime(minutes: minutes)) ago"
        }
        return "Offline"
    }

    var presenceIsLive: Bool {
        otherParticipantIsOnline
    }

    /// Most recent message for the inbox preview.
    var lastMessage: Message? {
        messages.max(by: { $0.sentAt < $1.sentAt })
    }

    /// Minutes since the last message, for the inbox timestamp.
    var lastMinutesAgo: Int {
        if let lastMessageAt {
            return max(0, Int(Date().timeIntervalSince(lastMessageAt) / 60))
        }
        return max(0, Int(Date().timeIntervalSince(lastActiveAt) / 60))
    }

    init(
        id: UUID,
        clientID: UUID,
        clientName: String,
        initials: String,
        messages: [Message] = [],
        isUnread: Bool = false,
        lastActiveAt: Date = .now,
        lastMessagePreview: String? = nil,
        lastMessageAt: Date? = nil,
        otherParticipantUserID: UUID? = nil,
        otherParticipantIsOnline: Bool = false,
        otherParticipantLastSeen: Date? = nil
    ) {
        self.id = id
        self.clientID = clientID
        self.clientName = clientName
        self.initials = initials
        self.messages = messages
        self.isUnread = isUnread
        self.lastActiveAt = lastActiveAt
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageAt = lastMessageAt
        self.otherParticipantUserID = otherParticipantUserID
        self.otherParticipantIsOnline = otherParticipantIsOnline
        self.otherParticipantLastSeen = otherParticipantLastSeen
    }
}

/// Compact relative-time formatting ("now", "12m", "3h", "2d").
func relativeTime(minutes: Int) -> String {
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes)m" }
    if minutes < 60 * 24 { return "\(minutes / 60)h" }
    return "\(minutes / (60 * 24))d"
}
