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
    /// True when the trainer (current user) sent it — renders on the right.
    var isOutgoing: Bool
    /// Minutes ago this message was sent, used for the seeded timeline ordering.
    var minutesAgo: Int
    var reaction: Reaction?

    init(
        id: UUID = UUID(),
        kind: MessageKind,
        isOutgoing: Bool,
        minutesAgo: Int = 0,
        reaction: Reaction? = nil
    ) {
        self.id = id
        self.kind = kind
        self.isOutgoing = isOutgoing
        self.minutesAgo = minutesAgo
        self.reaction = reaction
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
    /// Minutes since the client was last active, drives the "Active 10m ago" line.
    var lastActiveMinutes: Int

    /// Most recent message for the inbox preview.
    var lastMessage: Message? {
        messages.max(by: { $0.minutesAgo > $1.minutesAgo })
    }

    /// Minutes since the last message, for the inbox timestamp.
    var lastMinutesAgo: Int {
        messages.map(\.minutesAgo).min() ?? 0
    }
}

/// Compact relative-time formatting ("now", "12m", "3h", "2d").
func relativeTime(minutes: Int) -> String {
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes)m" }
    if minutes < 60 * 24 { return "\(minutes / 60)h" }
    return "\(minutes / (60 * 24))d"
}
