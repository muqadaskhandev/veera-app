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
    /// Bumped on local unread changes so an in-flight poll can't wipe a newer WS update.
    private var inboxEpoch = 0

    /// Locally-persisted archive/delete state — the backend has no concept of
    /// either yet, so these live in UserDefaults keyed by conversation ID.
    private static let archivedDefaultsKey = "com.verraos.archivedConversationIDs"
    private static let deletedDefaultsKey = "com.verraos.deletedConversationIDs"
    private var archivedIDs: Set<UUID>
    private var deletedIDs: Set<UUID>

    init(conversations: [Conversation] = []) {
        let archived = Self.loadIDSet(key: Self.archivedDefaultsKey)
        let deleted = Self.loadIDSet(key: Self.deletedDefaultsKey)
        self.archivedIDs = archived
        self.deletedIDs = deleted
        self.conversations = conversations.map { convo in
            var convo = convo
            convo.isArchived = archived.contains(convo.id)
            return convo
        }
    }

    /// Total unread messages across the inbox (local tallies; server only stores a boolean flag).
    var unreadCount: Int {
        conversations.reduce(0) { $0 + (($1.isArchived) ? 0 : max(0, $1.unreadMessageCount)) }
    }

    /// Search by client name; sorted most-recent first. Excludes archived threads.
    func inbox(search: String) -> [Conversation] {
        var result = conversations.filter { !$0.isArchived }
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.clientName.localizedCaseInsensitiveContains(query) }
        }
        return result.sorted { ($0.lastMessageAt ?? $0.lastActiveAt) > ($1.lastMessageAt ?? $1.lastActiveAt) }
    }

    /// Archived threads only, most-recent first.
    func archivedInbox(search: String = "") -> [Conversation] {
        var result = conversations.filter { $0.isArchived }
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.clientName.localizedCaseInsensitiveContains(query) }
        }
        return result.sorted { ($0.lastMessageAt ?? $0.lastActiveAt) > ($1.lastMessageAt ?? $1.lastActiveAt) }
    }

    var hasArchivedConversations: Bool {
        conversations.contains { $0.isArchived }
    }

    func conversation(id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    // MARK: Archive / delete

    @MainActor
    func archive(_ id: UUID) {
        archivedIDs.insert(id)
        persist(archivedIDs, key: Self.archivedDefaultsKey)
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].isArchived = true
        }
    }

    @MainActor
    func unarchive(_ id: UUID) {
        archivedIDs.remove(id)
        persist(archivedIDs, key: Self.archivedDefaultsKey)
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].isArchived = false
        }
    }

    @MainActor
    func delete(_ id: UUID) {
        deletedIDs.insert(id)
        archivedIDs.remove(id)
        persist(deletedIDs, key: Self.deletedDefaultsKey)
        persist(archivedIDs, key: Self.archivedDefaultsKey)
        conversations.removeAll { $0.id == id }
    }

    private static func loadIDSet(key: String) -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private func persist(_ ids: Set<UUID>, key: String) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
    }

    /// Clears a previously-deleted flag when the trainer actively re-engages
    /// with a thread (opens it or sends a message), so it isn't silently
    /// dropped again on the next server refresh.
    private func undeleteIfNeeded(_ id: UUID) {
        guard deletedIDs.remove(id) != nil else { return }
        persist(deletedIDs, key: Self.deletedDefaultsKey)
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
        let epochAtStart = inboxEpoch
        do {
            let dtos = try await VerraAPI.fetchConversations(accessToken: token)
            // A live unread/read change happened while this request was in flight — drop stale snapshot.
            guard epochAtStart == inboxEpoch else { return }

            var merged: [Conversation] = []
            for dto in dtos {
                guard !deletedIDs.contains(dto.id) else { continue }
                if let existing = conversations.first(where: { $0.id == dto.id }) {
                    // Server only has a boolean; keep the local tally while still unread.
                    let unreadCount: Int
                    if dto.isUnread {
                        unreadCount = max(existing.unreadMessageCount, 1)
                    } else {
                        unreadCount = 0
                    }
                    var convo = MessageLoader.conversation(
                        from: dto,
                        messages: existing.messages,
                        unreadMessageCount: unreadCount
                    )
                    convo.isUnread = unreadCount > 0
                    if existing.otherParticipantIsOnline, !convo.otherParticipantIsOnline {
                        convo.otherParticipantIsOnline = true
                        convo.otherParticipantLastSeen = nil
                    }
                    convo.isArchived = archivedIDs.contains(dto.id)
                    merged.append(convo)
                } else {
                    var convo = MessageLoader.conversation(from: dto)
                    convo.isArchived = archivedIDs.contains(dto.id)
                    merged.append(convo)
                }
            }
            conversations = merged
            isLoadedFromServer = true
        } catch {
            // Keep cached conversations when offline.
        }
    }

    @MainActor
    func clearActiveConversation() {
        activeConversationID = nil
    }

    @MainActor
    func loadMessages(for conversationID: UUID) async {
        guard let token = AuthStore.accessToken else { return }
        activeConversationID = conversationID
        undeleteIfNeeded(conversationID)
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
            // Re-check for a race-created local conversation before minting a new one.
            if let existing = conversations.first(where: { $0.clientID == client.id }) {
                return existing.id
            }
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
            // The server call failed — prefer reusing any conversation for this
            // client that already exists locally (e.g. from a concurrent call
            // or a since-completed refresh) instead of minting another local
            // placeholder, which would otherwise produce duplicate threads.
            if let existing = conversations.first(where: { $0.clientID == client.id }) {
                return existing.id
            }
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
        undeleteIfNeeded(id)
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
            let wasNew = append(MessageLoader.message(from: dto), to: dto.conversationID)
            updatePreview(for: dto.conversationID, preview: dto.body, at: dto.createdAt ?? .now)
            if wasNew, !dto.isOutgoing {
                if dto.conversationID == activeConversationID {
                    Task { await acknowledgeRead(conversationID: dto.conversationID) }
                } else {
                    markUnread(dto.conversationID)
                    Task { await acknowledgeDelivered(conversationID: dto.conversationID) }
                    let senderName = conversation(id: dto.conversationID)?.clientName ?? ""
                    let kind = MessageLoader.message(from: dto).kind
                    let copy = ChatNotificationRouter.alertCopy(senderName: senderName, kind: kind)
                    ChatPushService.showLocalNotification(
                        title: copy.title,
                        body: copy.body,
                        conversationID: dto.conversationID
                    )
                    ChatNotificationRouter.postIncomingChatAlert(
                        title: copy.title,
                        body: copy.body,
                        conversationID: dto.conversationID
                    )
                    NotificationCenter.default.post(name: .refreshNotifications, object: nil)
                }
            }
        case "conversation.read":
            // The *other* participant read the thread — update our outgoing ticks only.
            // Do NOT clear our inbox unread badge.
            if let id = event.conversationID {
                markOutgoingMessagesRead(in: id)
            }
        case "message.status":
            guard let dto = event.message else { return }
            applyMessageStatus(dto)
        case "message.reaction":
            guard let conversationID = event.conversationID,
                  let messageID = event.messageID else { return }
            updateMessages(in: conversationID) { messages in
                guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
                messages[index].reaction = event.reaction.flatMap { Reaction(rawValue: $0) }
            }
        case "typing.start":
            if let id = event.conversationID { typingConversationIDs.insert(id) }
        case "typing.stop":
            if let id = event.conversationID { typingConversationIDs.remove(id) }
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
        case "notification.new":
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = event.preview?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title, !title.isEmpty, let body, !body.isEmpty else { break }
            let opensSchedule = [
                "New session scheduled",
                "Session cancelled",
            ].contains(title)
            ChatPushService.showLocalNotification(title: title, body: body, opensSchedule: opensSchedule)
            ChatNotificationRouter.postIncomingChatAlert(title: title, body: body, opensSchedule: opensSchedule)
            NotificationCenter.default.post(name: .refreshNotifications, object: nil)
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
    @discardableResult
    private func append(_ message: Message, to conversationID: UUID) -> Bool {
        var inserted = false
        updateMessages(in: conversationID) { messages in
            guard !messages.contains(where: { $0.id == message.id }) else { return }
            messages.append(message)
            inserted = true
        }
        if inserted, let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].lastActiveAt = message.sentAt
        }
        return inserted
    }

    @MainActor
    private func applyMessages(_ messages: [Message], to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let previous = conversations[index].messages
        let existingStatus = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.deliveryStatus) })
        var byID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        for message in messages {
            var next = message
            if next.isOutgoing, let cached = existingStatus[next.id] {
                next.deliveryStatus = maxDeliveryStatus(cached, next.deliveryStatus)
            }
            byID[next.id] = next
        }
        conversations[index].messages = byID.values.sorted { $0.sentAt < $1.sentAt }
    }

    @MainActor
    private func updateMessages(in conversationID: UUID, _ transform: (inout [Message]) -> Void) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        var messages = conversations[index].messages
        transform(&messages)
        conversations[index].messages = messages
    }

    private func maxDeliveryStatus(_ lhs: MessageDeliveryStatus, _ rhs: MessageDeliveryStatus) -> MessageDeliveryStatus {
        let order: [MessageDeliveryStatus] = [.sent, .delivered, .read]
        let li = order.firstIndex(of: lhs) ?? 0
        let ri = order.firstIndex(of: rhs) ?? 0
        return order[max(li, ri)]
    }

    @MainActor
    private func updatePreview(for conversationID: UUID, preview: String, at date: Date) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].lastMessagePreview = preview
        conversations[index].lastMessageAt = date
        conversations[index].lastActiveAt = date
    }

    @MainActor
    private func markOutgoingMessagesRead(in conversationID: UUID) {
        updateMessages(in: conversationID) { messages in
            for index in messages.indices where messages[index].isOutgoing {
                messages[index].deliveryStatus = .read
            }
        }
    }

    @MainActor
    private func applyMessageStatus(_ dto: MessageDTO) {
        updateMessages(in: dto.conversationID) { messages in
            guard let index = messages.firstIndex(where: { $0.id == dto.id }) else { return }
            guard messages[index].isOutgoing else { return }
            messages[index].deliveryStatus =
                MessageDeliveryStatus(rawValue: dto.status) ?? messages[index].deliveryStatus
        }
    }

    @MainActor
    private func acknowledgeRead(conversationID: UUID) async {
        guard let token = AuthStore.accessToken else { return }
        _ = try? await VerraAPI.markConversationRead(conversationID: conversationID, accessToken: token)
        markReadLocal(conversationID)
    }

    @MainActor
    private func acknowledgeDelivered(conversationID: UUID) async {
        guard let token = AuthStore.accessToken else { return }
        guard let dtos = try? await VerraAPI.markConversationDelivered(conversationID: conversationID, accessToken: token) else {
            return
        }
        for dto in dtos {
            applyMessageStatus(dto)
        }
    }

    @MainActor
    private func markReadLocal(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        inboxEpoch += 1
        conversations[index].isUnread = false
        conversations[index].unreadMessageCount = 0
    }

    @MainActor
    private func markUnread(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        inboxEpoch += 1
        conversations[index].isUnread = true
        conversations[index].unreadMessageCount += 1
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
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { break }
                await refreshFromServer()
                // Soft-refresh the open thread only — don't re-mark-read every poll.
                if let activeConversationID {
                    await softReloadMessages(for: activeConversationID)
                }
            }
        }
    }

    @MainActor
    private func softReloadMessages(for conversationID: UUID) async {
        guard let token = AuthStore.accessToken else { return }
        do {
            let page = try await VerraAPI.fetchMessages(conversationID: conversationID, accessToken: token)
            applyMessages(page.messages.map(MessageLoader.message(from:)), to: conversationID)
        } catch {
            // Keep existing thread content.
        }
    }
}
