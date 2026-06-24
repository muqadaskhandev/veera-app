//
//  MessageStore.swift
//  VerraOS
//

import SwiftUI

/// Owns the conversation inbox shared by the Messages tab. Starts empty;
/// supports search, sending, reactions, and a lightweight simulated client reply
/// so threads feel alive.
@Observable
final class MessageStore {
    var conversations: [Conversation]

    init(conversations: [Conversation] = MessageStore.seed()) {
        self.conversations = conversations
    }

    var unreadCount: Int {
        conversations.filter(\.isUnread).count
    }

    /// Search by client name; sorted most-recent first.
    func inbox(search: String) -> [Conversation] {
        var result = conversations
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.clientName.localizedCaseInsensitiveContains(query) }
        }
        return result.sorted { $0.lastMinutesAgo < $1.lastMinutesAgo }
    }

    func conversation(id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    /// Returns the existing thread for a client, creating one if needed.
    func threadID(for client: Client) -> UUID {
        if let existing = conversations.first(where: { $0.clientID == client.id }) {
            return existing.id
        }
        let convo = Conversation(
            id: UUID(),
            clientID: client.id,
            clientName: client.name,
            initials: client.initials,
            messages: [],
            isUnread: false,
            lastActiveMinutes: 2
        )
        conversations.insert(convo, at: 0)
        return convo.id
    }

    // MARK: Mutations

    func markRead(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isUnread = false
    }

    func send(_ kind: MessageKind, to id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let message = Message(kind: kind, isOutgoing: true, minutesAgo: 0)
        bumpTimestamps(at: index)
        conversations[index].messages.append(message)
    }

    /// Adds a simulated incoming reply after a short delay (used to keep demo
    /// threads feeling responsive).
    @MainActor
    func simulateReply(to id: UUID) async {
        try? await Task.sleep(for: .seconds(1.8))
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let replies = ["Got it, thanks!", "Sounds good 💪", "See you then!", "Perfect 🙌", "On my way"]
        bumpTimestamps(at: index)
        let reply = Message(kind: .text(replies.randomElement() ?? "👍"), isOutgoing: false, minutesAgo: 0)
        conversations[index].messages.append(reply)
        conversations[index].lastActiveMinutes = 0
    }

    func setReaction(_ reaction: Reaction?, messageID: UUID, in conversationID: UUID) {
        guard let cIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let mIndex = conversations[cIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        let current = conversations[cIndex].messages[mIndex].reaction
        conversations[cIndex].messages[mIndex].reaction = (current == reaction) ? nil : reaction
    }

    /// Nudges existing message timestamps so the newly appended one reads "now".
    private func bumpTimestamps(at index: Int) {
        for i in conversations[index].messages.indices {
            conversations[index].messages[i].minutesAgo += 1
        }
    }

    /// A single conversation between a client and their coach, written from the
    /// client's perspective (their messages are outgoing). Used by the client
    /// experience, which has exactly one thread.
    static func clientThread(for client: Client) -> Conversation {
        Conversation(
            id: UUID(),
            clientID: client.id,
            clientName: client.name,
            initials: client.initials,
            messages: [],
            isUnread: false,
            lastActiveMinutes: 0
        )
    }

    // MARK: Seed

    /// The inbox starts empty — threads appear as the trainer messages real clients.
    static func seed() -> [Conversation] { [] }
}
