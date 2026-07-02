//
//  MessageStore.swift
//  VerraOS
//

import SwiftUI

/// Owns the conversation inbox shared by the Messages tab. Syncs with the API,
/// receives live updates over WebSocket, and queues sends when offline.
@Observable
final class MessageStore {
    var conversations: [Conversation]
    var isLoadedFromServer = false
    var typingConversationIDs: Set<UUID> = []

    private var pollTask: Task<Void, Never>?
    private var activeConversationID: UUID?

    init(conversations: [Conversation] = []) {
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
        return result.sorted { ($0.lastMessageAt ?? $0.lastActiveAt) > ($1.lastMessageAt ?? $1.lastActiveAt) }
    }

    func conversation(id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    // MARK: Server sync

    @MainActor
    func start(accessToken: String) async {
        ChatWebSocketService.shared.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }
        ChatWebSocketService.shared.connect(accessToken: accessToken)
        await refreshFromServer()
        await flushOfflineQueue()
        startPolling(accessToken: accessToken)
        await ChatPushService.registerIfNeeded()
    }

    @MainActor
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        ChatWebSocketService.shared.disconnect()
        ChatWebSocketService.shared.onEvent = nil
    }

    @MainActor
    func refreshFromServer() async {
        guard let token = AuthStore.accessToken else { return }
        do {
            let dtos = try await VerraAPI.fetchConversations(accessToken: token)
            var merged: [Conversation] = []
            for dto in dtos {
                if let existing = conversations.first(where: { $0.id == dto.id }) {
                    var convo = MessageLoader.conversation(from: dto, messages: existing.messages)
                    merged.append(convo)
                } else {
                    merged.append(MessageLoader.conversation(from: dto))
                }
            }
            conversations = merged
            isLoadedFromServer = true
        } catch {
            // Keep cached conversations when offline.
        }
    }

    @MainActor
    func loadMessages(for conversationID: UUID) async {
        guard let token = AuthStore.accessToken else { return }
        activeConversationID = conversationID
        do {
            let page = try await VerraAPI.fetchMessages(conversationID: conversationID, accessToken: token)
            applyMessages(page.messages.map(MessageLoader.message(from:)), to: conversationID)
            _ = try? await VerraAPI.markConversationRead(conversationID: conversationID, accessToken: token)
            markReadLocal(conversationID)
        } catch {
            // Keep existing thread content.
        }
    }

    @MainActor
    func threadID(for client: Client) async -> UUID {
        if let existing = conversations.first(where: { $0.clientID == client.id }) {
            return existing.id
        }
        guard let token = AuthStore.accessToken else {
            let convo = Conversation(
                id: UUID(),
                clientID: client.id,
                clientName: client.name,
                initials: client.initials
            )
            conversations.insert(convo, at: 0)
            return convo.id
        }

        do {
            let dto = try await VerraAPI.getOrCreateConversation(clientID: client.id, accessToken: token)
            let convo = MessageLoader.conversation(from: dto)
            if let index = conversations.firstIndex(where: { $0.id == convo.id }) {
                conversations[index] = convo
            } else {
                conversations.insert(convo, at: 0)
            }
            return convo.id
        } catch {
            let convo = Conversation(
                id: UUID(),
                clientID: client.id,
                clientName: client.name,
                initials: client.initials
            )
            conversations.insert(convo, at: 0)
            return convo.id
        }
    }

    @MainActor
    func ensureClientThread() async -> UUID? {
        guard let token = AuthStore.accessToken else { return conversations.first?.id }
        await refreshFromServer()
        if let existing = conversations.first {
            return existing.id
        }
        do {
            let dto = try await VerraAPI.getOrCreateMyConversation(accessToken: token)
            let convo = MessageLoader.conversation(from: dto)
            conversations = [convo]
            return convo.id
        } catch {
            return conversations.first?.id
        }
    }

    // MARK: Mutations

    func markRead(_ id: UUID) {
        markReadLocal(id)
        Task { @MainActor in
            guard let token = AuthStore.accessToken else { return }
            _ = try? await VerraAPI.markConversationRead(conversationID: id, accessToken: token)
        }
    }

    @MainActor
    func send(_ kind: MessageKind, to id: UUID, attachmentURL: String? = nil) async {
        guard let token = AuthStore.accessToken else {
            enqueueOffline(kind: kind, conversationID: id, attachmentURL: attachmentURL)
            return
        }

        do {
            let dto = try await VerraAPI.sendMessage(
                conversationID: id,
                kind: kind,
                attachmentURL: attachmentURL,
                accessToken: token
            )
            append(MessageLoader.message(from: dto), to: id)
            updatePreview(for: id, preview: kind.preview, at: dto.createdAt ?? .now)
        } catch {
            enqueueOffline(kind: kind, conversationID: id, attachmentURL: attachmentURL)
        }
    }

    @MainActor
    @discardableResult
    func sendAttachment(_ upload: ChatMediaService.PreparedUpload, to conversationID: UUID) async -> Bool {
        guard let token = AuthStore.accessToken else { return false }

        do {
            let response = try await VerraAPI.uploadChatAttachment(
                conversationID: conversationID,
                data: upload.data,
                filename: upload.filename,
                mimeType: upload.mimeType,
                accessToken: token
            )
            let dto = try await VerraAPI.sendMessage(
                conversationID: conversationID,
                kind: upload.kind,
                attachmentURL: response.attachmentURL,
                accessToken: token
            )
            append(MessageLoader.message(from: dto), to: conversationID)
            updatePreview(for: conversationID, preview: upload.kind.preview, at: dto.createdAt ?? .now)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    func setReaction(_ reaction: Reaction?, messageID: UUID, in conversationID: UUID) {
        guard let cIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let mIndex = conversations[cIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }

        let current = conversations[cIndex].messages[mIndex].reaction
        let next = (current == reaction) ? nil : reaction
        conversations[cIndex].messages[mIndex].reaction = next

        Task {
            guard let token = AuthStore.accessToken else { return }
            _ = try? await VerraAPI.setMessageReaction(messageID: messageID, reaction: next, accessToken: token)
        }
    }

    @MainActor
    func sendTyping(conversationID: UUID, isTyping: Bool) {
        ChatWebSocketService.shared.sendTyping(conversationID: conversationID, isTyping: isTyping)
    }

    static func clientThread(for client: Client) -> Conversation {
        Conversation(
            id: UUID(),
            clientID: client.id,
            clientName: client.name,
            initials: client.initials
        )
    }

    // MARK: Private

    @MainActor
    private func handle(event: ChatEventDTO) {
        switch event.type {
        case "message.new":
            guard let dto = event.message else { return }
            append(MessageLoader.message(from: dto), to: dto.conversationID)
            updatePreview(for: dto.conversationID, preview: dto.body, at: dto.createdAt ?? .now)
            if dto.conversationID != activeConversationID {
                markUnread(dto.conversationID)
                ChatPushService.showLocalNotification(
                    title: conversation(id: dto.conversationID)?.clientName ?? "New message",
                    body: event.preview ?? dto.body,
                    conversationID: dto.conversationID
                )
            }
        case "message.reaction":
            guard let conversationID = event.conversationID,
                  let messageID = event.messageID,
                  let cIndex = conversations.firstIndex(where: { $0.id == conversationID }),
                  let mIndex = conversations[cIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
            conversations[cIndex].messages[mIndex].reaction = event.reaction.flatMap { Reaction(rawValue: $0) }
        case "typing.start":
            if let id = event.conversationID { typingConversationIDs.insert(id) }
        case "typing.stop":
            if let id = event.conversationID { typingConversationIDs.remove(id) }
        case "conversation.read":
            if let id = event.conversationID { markReadLocal(id) }
        case "presence.update":
            guard let userID = event.userID else { break }
            applyPresence(
                userID: userID,
                isOnline: event.isOnline ?? false,
                lastSeen: event.lastSeen
            )
        case "presence.snapshot":
            guard let states = event.presence else { break }
            for state in states {
                applyPresence(userID: state.userID, isOnline: state.isOnline, lastSeen: state.lastSeen)
            }
        default:
            break
        }
    }

    @MainActor
    private func applyPresence(userID: UUID, isOnline: Bool, lastSeen: Date?) {
        for index in conversations.indices {
            guard conversations[index].otherParticipantUserID == userID else { continue }
            conversations[index].otherParticipantIsOnline = isOnline
            conversations[index].otherParticipantLastSeen = isOnline ? nil : (lastSeen ?? conversations[index].otherParticipantLastSeen)
        }
    }

    @MainActor
    private func append(_ message: Message, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        if conversations[index].messages.contains(where: { $0.id == message.id }) { return }
        conversations[index].messages.append(message)
        conversations[index].lastActiveAt = message.sentAt
    }

    @MainActor
    private func applyMessages(_ messages: [Message], to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].messages = messages.sorted { $0.sentAt < $1.sentAt }
    }

    @MainActor
    private func updatePreview(for conversationID: UUID, preview: String, at date: Date) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].lastMessagePreview = preview
        conversations[index].lastMessageAt = date
        conversations[index].lastActiveAt = date
    }

    @MainActor
    private func markReadLocal(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isUnread = false
    }

    @MainActor
    private func markUnread(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isUnread = true
    }

    @MainActor
    private func enqueueOffline(kind: MessageKind, conversationID: UUID, attachmentURL: String? = nil) {
        let pending = PendingChatMessage(conversationID: conversationID, kind: kind, attachmentURL: attachmentURL)
        ChatOfflineQueue.enqueue(pending)
        let optimistic = Message(kind: kind, isOutgoing: true, sentAt: .now, attachmentURL: attachmentURL)
        append(optimistic, to: conversationID)
        updatePreview(for: conversationID, preview: kind.preview, at: .now)
    }

    @MainActor
    private func flushOfflineQueue() async {
        guard let token = AuthStore.accessToken else { return }
        let pending = ChatOfflineQueue.load()
        guard !pending.isEmpty else { return }
        do {
            _ = try await VerraAPI.flushOfflineQueue(pending, accessToken: token)
            ChatOfflineQueue.clear()
            await refreshFromServer()
        } catch {
            // Retry on next launch.
        }
    }

    @MainActor
    private func startPolling(accessToken: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refreshFromServer()
                if let activeConversationID {
                    await loadMessages(for: activeConversationID)
                }
            }
        }
    }
}
