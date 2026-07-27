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
    /// Maps local placeholder conversation IDs → canonical server IDs after adoption.
    private var conversationIDAliases: [UUID: UUID] = [:]

    init(conversations: [Conversation] = []) {
        self.conversations = conversations
        // Legacy local-only archive/delete keys — server is now source of truth.
        UserDefaults.standard.removeObject(forKey: "com.verraos.archivedConversationIDs")
        UserDefaults.standard.removeObject(forKey: "com.verraos.deletedConversationIDs")
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

    /// Active (non-archived) conversation count for the inbox header.
    var activeConversationCount: Int {
        conversations.filter { !$0.isArchived }.count
    }

    /// Instant local thread for a client — used so Messages can push before the
    /// network round-trip finishes. Reuses any existing thread for that client.
    @MainActor
    @discardableResult
    func ensureLocalThread(for client: Client) -> Conversation {
        if let existing = conversations.first(where: { $0.clientID == client.id }) {
            // Opening from a client card restores an archived thread.
            if existing.isArchived {
                unarchive(existing.id)
                return conversations.first(where: { $0.id == existing.id }) ?? existing
            }
            return existing
        }
        let convo = Conversation(
            id: UUID(),
            clientID: client.id,
            clientName: client.name,
            initials: client.initials
        )
        conversations.insert(convo, at: 0)
        return convo
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
        let canonical = canonicalConversationID(id)
        return conversations.first { $0.id == canonical }
    }

    /// Resolves placeholder IDs to the server conversation they were adopted into.
    func canonicalConversationID(_ id: UUID) -> UUID {
        var current = id
        var seen: Set<UUID> = []
        while let next = conversationIDAliases[current], !seen.contains(next) {
            seen.insert(current)
            current = next
        }
        return current
    }

    // MARK: Archive / delete

    @MainActor
    func archive(_ id: UUID) {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].isArchived = true
        }
        Task { await persistArchive(true, for: id) }
    }

    @MainActor
    func unarchive(_ id: UUID) {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].isArchived = false
        }
        Task { await persistArchive(false, for: id) }
    }

    @MainActor
    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        Task {
            guard let token = AuthStore.accessToken else { return }
            try? await VerraAPI.deleteConversation(conversationID: id, accessToken: token)
        }
    }

    @MainActor
    private func persistArchive(_ archived: Bool, for id: UUID) async {
        guard let token = AuthStore.accessToken else { return }
        if let dto = try? await VerraAPI.setConversationArchived(
            conversationID: id,
            archived: archived,
            accessToken: token
        ), let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].isArchived = dto.isArchived ?? archived
        }
    }

    // MARK: Server sync

    @MainActor
    func start(accessToken: String) async {
        // Open the socket immediately so live events aren't delayed behind inbox load.
        ChatWebSocketService.shared.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }
        ChatWebSocketService.shared.onReconnect = { [weak self] in
            Task { @MainActor in
                await self?.catchUpAfterReconnect()
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
        ChatWebSocketService.shared.onReconnect = nil
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
                    merged.append(convo)
                } else {
                    merged.append(MessageLoader.conversation(from: dto))
                }
            }
            // Keep optimistic local placeholders that haven't been adopted yet.
            for local in conversations where !merged.contains(where: { $0.id == local.id || $0.clientID == local.clientID }) {
                merged.append(local)
            }
            // One thread per client — drop duplicate rows (e.g. from races before
            // the unique index) and migrate any local placeholder messages.
            conversations = coalesceByClient(merged)
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
        let id = canonicalConversationID(conversationID)
        activeConversationID = id
        do {
            let page = try await VerraAPI.fetchMessages(conversationID: id, accessToken: token)
            applyMessages(page.messages.map(MessageLoader.message(from:)), to: id)
            _ = try? await VerraAPI.markConversationRead(conversationID: id, accessToken: token)
            markReadLocal(id)
        } catch {
            // Placeholder conversation IDs 404 — adopt the server thread and load that instead.
            if isConversationNotFound(error) {
                let resolved = await resolveServerConversationID(id)
                if resolved != id {
                    await loadMessages(for: resolved)
                }
            }
        }
    }

    @MainActor
    func threadID(for client: Client) async -> UUID {
        guard let token = AuthStore.accessToken else {
            return ensureLocalThread(for: client).id
        }

        do {
            let dto = try await VerraAPI.getOrCreateConversation(clientID: client.id, accessToken: token)
            return adoptServerConversation(MessageLoader.conversation(from: dto), for: client.id)
        } catch {
            // Prefer any local/server thread for this client over minting another.
            if let existing = conversations.first(where: { $0.clientID == client.id }) {
                return existing.id
            }
            // Last resort: refresh once, then local placeholder.
            await refreshFromServer()
            if let existing = conversations.first(where: { $0.clientID == client.id }) {
                return existing.id
            }
            return ensureLocalThread(for: client).id
        }
    }

    /// Replaces any local placeholder for `clientID` with the canonical server
    /// conversation, migrating messages so the UI keeps a single continuous thread.
    @MainActor
    @discardableResult
    private func adoptServerConversation(_ server: Conversation, for clientID: UUID) -> UUID {
        var adopted = server

        let placeholders = conversations.filter { $0.clientID == clientID && $0.id != server.id }
        let migrated = placeholders.flatMap(\.messages)
        if !migrated.isEmpty {
            var messages = adopted.messages
            for message in migrated where !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
            }
            adopted.messages = messages.sorted { $0.sentAt < $1.sentAt }
        }

        conversations.removeAll { $0.clientID == clientID && $0.id != server.id }

        // Offline queue may still reference the local placeholder UUID.
        let placeholderIDs = placeholders.map(\.id)
        ChatOfflineQueue.rewriteConversationID(from: placeholderIDs, to: server.id)
        for oldID in placeholderIDs {
            conversationIDAliases[oldID] = server.id
        }

        if let index = conversations.firstIndex(where: { $0.id == server.id }) {
            if conversations[index].messages.count > adopted.messages.count {
                adopted.messages = conversations[index].messages
            }
            conversations[index] = adopted
        } else {
            conversations.insert(adopted, at: 0)
        }
        conversations = coalesceByClient(conversations)
        if let active = activeConversationID, placeholderIDs.contains(active) {
            activeConversationID = server.id
        }
        return server.id
    }

    /// Keeps one conversation per client (most recent / most messages wins).
    private func coalesceByClient(_ list: [Conversation]) -> [Conversation] {
        var byClient: [UUID: Conversation] = [:]
        for convo in list {
            guard let existing = byClient[convo.clientID] else {
                byClient[convo.clientID] = convo
                continue
            }
            let existingScore = (existing.lastMessageAt ?? existing.lastActiveAt, existing.messages.count)
            let newScore = (convo.lastMessageAt ?? convo.lastActiveAt, convo.messages.count)
            var keep = (newScore.0, newScore.1) > (existingScore.0, existingScore.1) ? convo : existing
            let drop = keep.id == convo.id ? existing : convo
            var messages = keep.messages
            for message in drop.messages where !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
            }
            keep.messages = messages.sorted { $0.sentAt < $1.sentAt }
            // Prefer the archive flag from the row we keep (server snapshot).
            if keep.id == convo.id {
                keep.isArchived = convo.isArchived
            } else {
                keep.isArchived = existing.isArchived
            }
            byClient[convo.clientID] = keep
        }
        return Array(byClient.values)
    }

    @MainActor
    func ensureClientThread() async -> UUID? {
        guard let token = AuthStore.accessToken else { return conversations.first?.id }
        if !isLoadedFromServer {
            await refreshFromServer()
        }
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
        // Show the bubble immediately — waiting on the network made sends feel laggy.
        let optimisticID = UUID()
        let optimistic = Message(
            id: optimisticID,
            kind: kind,
            isOutgoing: true,
            sentAt: .now,
            attachmentURL: attachmentURL,
            deliveryStatus: .sent
        )
        append(optimistic, to: id)
        updatePreview(for: id, preview: kind.preview, at: .now)
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].isArchived = false
        }

        guard let token = AuthStore.accessToken else {
            ChatOfflineQueue.enqueue(
                PendingChatMessage(conversationID: id, kind: kind, attachmentURL: attachmentURL)
            )
            return
        }

        do {
            let dto = try await VerraAPI.sendMessage(
                conversationID: id,
                kind: kind,
                attachmentURL: attachmentURL,
                accessToken: token
            )
            replaceMessage(optimisticID, with: MessageLoader.message(from: dto), in: id)
            updatePreview(for: id, preview: kind.preview, at: dto.createdAt ?? .now)
        } catch {
            // Local placeholder IDs 404 — resolve the canonical server thread and retry once.
            if isConversationNotFound(error),
               let retried = await retrySendAfterResolve(
                kind: kind,
                attachmentURL: attachmentURL,
                optimisticID: optimisticID,
                from: id,
                accessToken: token
               ) {
                let dest = retried.conversationID
                replaceMessage(optimisticID, with: MessageLoader.message(from: retried), in: dest)
                updatePreview(for: dest, preview: kind.preview, at: retried.createdAt ?? .now)
                return
            }
            removeMessage(optimisticID, from: id)
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

            // Bubble appears as soon as the file is uploaded; message create is usually fast after that.
            let optimisticID = UUID()
            let optimistic = Message(
                id: optimisticID,
                kind: upload.kind,
                isOutgoing: true,
                sentAt: .now,
                attachmentURL: response.attachmentURL,
                deliveryStatus: .sent
            )
            append(optimistic, to: conversationID)
            updatePreview(for: conversationID, preview: upload.kind.preview, at: .now)
            if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
                conversations[index].isArchived = false
            }

            do {
                let dto = try await VerraAPI.sendMessage(
                    conversationID: conversationID,
                    kind: upload.kind,
                    attachmentURL: response.attachmentURL,
                    accessToken: token
                )
                replaceMessage(optimisticID, with: MessageLoader.message(from: dto), in: conversationID)
                updatePreview(for: conversationID, preview: upload.kind.preview, at: dto.createdAt ?? .now)
                return true
            } catch {
                if isConversationNotFound(error),
                   let retried = await retrySendAfterResolve(
                    kind: upload.kind,
                    attachmentURL: response.attachmentURL,
                    optimisticID: optimisticID,
                    from: conversationID,
                    accessToken: token
                   ) {
                    replaceMessage(optimisticID, with: MessageLoader.message(from: retried), in: retried.conversationID)
                    updatePreview(for: retried.conversationID, preview: upload.kind.preview, at: retried.createdAt ?? .now)
                    return true
                }
                removeMessage(optimisticID, from: conversationID)
                enqueueOffline(
                    kind: upload.kind,
                    conversationID: conversationID,
                    attachmentURL: response.attachmentURL
                )
                return true
            }
        } catch {
            // Upload 404 on placeholder — resolve and retry the whole attachment send once.
            if isConversationNotFound(error) {
                let resolved = await resolveServerConversationID(conversationID)
                if resolved != conversationID {
                    return await sendAttachment(upload, to: resolved)
                }
            }
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
            Task { @MainActor in
                await ingestIncomingMessage(dto)
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

    /// Applies a live incoming message immediately. Missing threads get a stub
    /// so the bubble isn't blocked behind a full inbox refresh.
    @MainActor
    private func ingestIncomingMessage(_ dto: MessageDTO) async {
        ensureStubConversation(for: dto)

        let wasNew = append(MessageLoader.message(from: dto), to: dto.conversationID)
        updatePreview(for: dto.conversationID, preview: dto.body, at: dto.createdAt ?? .now)

        // Fill in client name / avatar without delaying the bubble.
        if conversations.first(where: { $0.id == canonicalConversationID(dto.conversationID) })?.clientName == "Chat" {
            Task { @MainActor in
                await refreshFromServer()
            }
        }

        guard wasNew, !dto.isOutgoing else { return }

        let conversationID = canonicalConversationID(dto.conversationID)
        if activeConversationID == conversationID {
            await acknowledgeRead(conversationID: conversationID)
        } else {
            markUnread(conversationID)
            await acknowledgeDelivered(conversationID: conversationID)
            let senderName = conversation(id: conversationID)?.clientName ?? ""
            let kind = MessageLoader.message(from: dto).kind
            let copy = ChatNotificationRouter.alertCopy(senderName: senderName, kind: kind)
            ChatPushService.showLocalNotification(
                title: copy.title,
                body: copy.body,
                conversationID: conversationID
            )
            ChatNotificationRouter.postIncomingChatAlert(
                title: copy.title,
                body: copy.body,
                conversationID: conversationID
            )
            NotificationCenter.default.post(name: .refreshNotifications, object: nil)
        }
    }

    /// Creates a temporary conversation row so `append` can succeed before inbox sync.
    @MainActor
    private func ensureStubConversation(for dto: MessageDTO) {
        let id = canonicalConversationID(dto.conversationID)
        guard conversations.first(where: { $0.id == id }) == nil else { return }
        let message = MessageLoader.message(from: dto)
        conversations.insert(
            Conversation(
                id: dto.conversationID,
                clientID: dto.conversationID,
                clientName: "Chat",
                initials: "?",
                messages: [],
                isUnread: !dto.isOutgoing,
                unreadMessageCount: dto.isOutgoing ? 0 : 1,
                lastActiveAt: dto.createdAt ?? .now,
                lastMessagePreview: message.kind.preview,
                lastMessageAt: dto.createdAt,
                otherParticipantUserID: dto.isOutgoing ? nil : dto.senderUserID
            ),
            at: 0
        )
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
        let id = canonicalConversationID(conversationID)
        var inserted = false
        updateMessages(in: id) { messages in
            guard !messages.contains(where: { $0.id == message.id }) else { return }
            messages.append(message)
            inserted = true
        }
        if inserted, let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].lastActiveAt = message.sentAt
        }
        return inserted
    }

    /// Swaps a temporary optimistic bubble for the server-confirmed message.
    /// If a live `message.new` event already inserted the server row, just drop the temp.
    @MainActor
    private func replaceMessage(_ optimisticID: UUID, with server: Message, in conversationID: UUID) {
        let id = canonicalConversationID(conversationID)
        updateMessages(in: id) { messages in
            if let index = messages.firstIndex(where: { $0.id == optimisticID }) {
                if messages.contains(where: { $0.id == server.id }) {
                    messages.remove(at: index)
                } else {
                    messages[index] = server
                }
            } else if !messages.contains(where: { $0.id == server.id }) {
                messages.append(server)
            }
        }
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].lastActiveAt = server.sentAt
        }
    }

    @MainActor
    private func removeMessage(_ messageID: UUID, from conversationID: UUID) {
        updateMessages(in: canonicalConversationID(conversationID)) { messages in
            messages.removeAll { $0.id == messageID }
        }
    }

    @MainActor
    private func applyMessages(_ messages: [Message], to conversationID: UUID) {
        let id = canonicalConversationID(conversationID)
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
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
        let id = canonicalConversationID(conversationID)
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
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
        let id = canonicalConversationID(conversationID)
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
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
            let incoming = MessageDeliveryStatus(rawValue: dto.status) ?? messages[index].deliveryStatus
            messages[index].deliveryStatus = maxDeliveryStatus(messages[index].deliveryStatus, incoming)
        }
    }

    /// Ensures we POST against the canonical server conversation, not a local placeholder UUID.
    @MainActor
    private func resolveServerConversationID(_ id: UUID) async -> UUID {
        guard let token = AuthStore.accessToken,
              let convo = conversations.first(where: { $0.id == id }) else {
            return id
        }

        // Trainer path — get-or-create by client id.
        if let dto = try? await VerraAPI.getOrCreateConversation(
            clientID: convo.clientID,
            accessToken: token
        ) {
            return adoptServerConversation(MessageLoader.conversation(from: dto), for: convo.clientID)
        }

        // Client path — single "mine" thread with their coach.
        if let mine = try? await VerraAPI.getOrCreateMyConversation(accessToken: token) {
            let adopted = MessageLoader.conversation(from: mine)
            let placeholders = conversations.filter { $0.id == id && $0.id != adopted.id }
            var merged = adopted
            let migrated = placeholders.flatMap(\.messages) + (conversations.first(where: { $0.id == adopted.id })?.messages ?? [])
            if !migrated.isEmpty {
                var messages = merged.messages
                for message in migrated where !messages.contains(where: { $0.id == message.id }) {
                    messages.append(message)
                }
                merged.messages = messages.sorted { $0.sentAt < $1.sentAt }
            }
            conversations.removeAll { $0.id == id && $0.id != adopted.id }
            ChatOfflineQueue.rewriteConversationID(from: [id], to: adopted.id)
            if let index = conversations.firstIndex(where: { $0.id == adopted.id }) {
                conversations[index] = merged
            } else {
                conversations.insert(merged, at: 0)
            }
            return adopted.id
        }

        return id
    }

    @MainActor
    private func retrySendAfterResolve(
        kind: MessageKind,
        attachmentURL: String?,
        optimisticID: UUID,
        from conversationID: UUID,
        accessToken: String
    ) async -> MessageDTO? {
        let resolved = await resolveServerConversationID(conversationID)
        guard resolved != conversationID || conversations.contains(where: { $0.id == resolved }) else {
            return nil
        }
        if resolved != conversationID {
            // Move the optimistic bubble onto the canonical thread.
            if let cIndex = conversations.firstIndex(where: { $0.id == conversationID }),
               let mIndex = conversations[cIndex].messages.firstIndex(where: { $0.id == optimisticID }) {
                let bubble = conversations[cIndex].messages.remove(at: mIndex)
                append(bubble, to: resolved)
            }
        }
        return try? await VerraAPI.sendMessage(
            conversationID: resolved,
            kind: kind,
            attachmentURL: attachmentURL,
            accessToken: accessToken
        )
    }

    private func isConversationNotFound(_ error: Error) -> Bool {
        guard case APIError.server(let reason) = error else { return false }
        return reason.localizedCaseInsensitiveContains("not found")
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
        let conversationID = canonicalConversationID(id)
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        inboxEpoch += 1
        conversations[index].isUnread = false
        conversations[index].unreadMessageCount = 0
    }

    @MainActor
    private func markUnread(_ id: UUID) {
        let conversationID = canonicalConversationID(id)
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
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

        // Rewrite any placeholder conversation IDs before flushing.
        var resolvedPending: [PendingChatMessage] = []
        for item in pending {
            let resolvedID = await resolveServerConversationID(item.conversationID)
            if resolvedID != item.conversationID {
                ChatOfflineQueue.rewriteConversationID(from: [item.conversationID], to: resolvedID)
            }
            resolvedPending.append(
                PendingChatMessage(
                    id: item.id,
                    conversationID: resolvedID,
                    kind: item.kind,
                    body: item.body,
                    attachmentURL: item.attachmentURL
                )
            )
        }

        do {
            _ = try await VerraAPI.flushOfflineQueue(resolvedPending, accessToken: token)
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
                // Poll faster while the socket is down so missed messages surface quickly.
                let interval: Double = ChatWebSocketService.shared.isConnected ? 12 : 3
                try? await Task.sleep(for: .seconds(interval))
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
    private func catchUpAfterReconnect() async {
        await refreshFromServer()
        if let activeConversationID {
            await softReloadMessages(for: activeConversationID)
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
