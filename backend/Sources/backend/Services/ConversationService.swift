import Fluent
import Vapor

enum ConversationService {
    static func list(for user: User, on database: any Database) async throws -> [ConversationDTO] {
        guard let role = user.userRole else { return [] }

        switch role {
        case .trainer:
            guard let trainer = try await Trainer.query(on: database)
                .filter(\.$user.$id == user.id!)
                .first() else {
                return []
            }
            let rows = try await Conversation.query(on: database)
                .filter(\.$trainer.$id == trainer.id!)
                .filter(\.$trainerIsDeleted == false)
                .sort(\.$lastMessageAt, .descending)
                .sort(\.$lastActiveAt, .descending)
                .all()
            var result: [ConversationDTO] = []
            for row in rows {
                result.append(try await ConversationDTO.make(from: row, viewer: user, on: database))
            }
            return result

        case .client:
            guard let client = try await Client.query(on: database)
                .filter(\.$user.$id == user.id!)
                .first() else {
                return []
            }
            let rows = try await Conversation.query(on: database)
                .filter(\.$client.$id == client.id!)
                .filter(\.$clientIsDeleted == false)
                .sort(\.$lastMessageAt, .descending)
                .all()
            var result: [ConversationDTO] = []
            for row in rows {
                result.append(try await ConversationDTO.make(from: row, viewer: user, on: database))
            }
            return result

        case .admin:
            let rows = try await Conversation.query(on: database)
                .filter(\.$trainerIsDeleted == false)
                .sort(\.$lastMessageAt, .descending)
                .all()
            var result: [ConversationDTO] = []
            for row in rows {
                result.append(try await ConversationDTO.make(from: row, viewer: user, on: database))
            }
            return result
        }
    }

    static func getOrCreate(forClientID clientID: UUID, trainerUser: User, on database: any Database) async throws -> Conversation {
        guard trainerUser.userRole == .trainer || trainerUser.userRole == .admin else {
            throw Abort(.forbidden)
        }

        guard let client = try await Client.find(clientID, on: database) else {
            throw Abort(.notFound, reason: "Client not found")
        }

        let viewerRole: UserRole = trainerUser.userRole == .admin ? .admin : .trainer

        if trainerUser.userRole == .admin {
            if let existing = try await Conversation.query(on: database)
                .filter(\.$trainer.$id == client.$trainer.id)
                .filter(\.$client.$id == clientID)
                .first() {
                return try await restoreIfHidden(existing, for: viewerRole, on: database)
            }

            let conversation = Conversation(
                trainerID: client.$trainer.id,
                clientID: clientID,
                clientName: client.name,
                initials: client.initials
            )
            do {
                try await conversation.save(on: database)
                return conversation
            } catch {
                if let existing = try await Conversation.query(on: database)
                    .filter(\.$trainer.$id == client.$trainer.id)
                    .filter(\.$client.$id == clientID)
                    .first() {
                    return try await restoreIfHidden(existing, for: viewerRole, on: database)
                }
                throw error
            }
        }

        guard let trainer = try await Trainer.query(on: database)
            .filter(\.$user.$id == trainerUser.id!)
            .first() else {
            throw Abort(.notFound, reason: "Trainer profile not found")
        }

        if client.$trainer.id != trainer.id {
            throw Abort(.forbidden)
        }

        if let existing = try await Conversation.query(on: database)
            .filter(\.$trainer.$id == client.$trainer.id)
            .filter(\.$client.$id == clientID)
            .first() {
            return try await restoreIfHidden(existing, for: .trainer, on: database)
        }

        let conversation = Conversation(
            trainerID: client.$trainer.id,
            clientID: clientID,
            clientName: client.name,
            initials: client.initials
        )
        do {
            try await conversation.save(on: database)
            return conversation
        } catch {
            // Concurrent create raced the unique (trainer_id, client_id) index —
            // return the row that won instead of surfacing an error (which caused
            // the iOS client to mint a duplicate local placeholder).
            if let existing = try await Conversation.query(on: database)
                .filter(\.$trainer.$id == client.$trainer.id)
                .filter(\.$client.$id == clientID)
                .first() {
                return try await restoreIfHidden(existing, for: .trainer, on: database)
            }
            throw error
        }
    }

    static func getOrCreateForCurrentClient(user: User, on database: any Database) async throws -> Conversation {
        guard user.userRole == .client else {
            throw Abort(.forbidden)
        }

        guard let client = try await Client.query(on: database)
            .filter(\.$user.$id == user.id!)
            .first() else {
            throw Abort(.notFound, reason: "Client profile not found")
        }

        if let existing = try await Conversation.query(on: database)
            .filter(\.$client.$id == client.id!)
            .first() {
            return try await restoreIfHidden(existing, for: .client, on: database)
        }

        let conversation = Conversation(
            trainerID: client.$trainer.id,
            clientID: try client.requireID(),
            clientName: client.name,
            initials: client.initials
        )
        do {
            try await conversation.save(on: database)
            return conversation
        } catch {
            if let existing = try await Conversation.query(on: database)
                .filter(\.$client.$id == client.id!)
                .first() {
                return try await restoreIfHidden(existing, for: .client, on: database)
            }
            throw error
        }
    }

    static func setArchived(
        conversationID: UUID,
        archived: Bool,
        for user: User,
        on database: any Database
    ) async throws -> ConversationDTO {
        let conversation = try await requireConversation(conversationID, for: user, on: database)
        let role = user.userRole ?? .client
        conversation.setDeleted(false, for: role)
        conversation.setArchived(archived, for: role)
        try await conversation.save(on: database)
        return try await ConversationDTO.make(from: conversation, viewer: user, on: database)
    }

    /// Soft-deletes the thread for this viewer only — history stays for the other participant.
    static func softDelete(
        conversationID: UUID,
        for user: User,
        on database: any Database
    ) async throws {
        let conversation = try await requireConversation(conversationID, for: user, on: database)
        let role = user.userRole ?? .client
        conversation.setDeleted(true, for: role)
        try await conversation.save(on: database)
    }

    static func requireConversation(_ id: UUID, for user: User, on database: any Database) async throws -> Conversation {
        guard let conversation = try await Conversation.find(id, on: database) else {
            throw Abort(.notFound, reason: "Conversation not found")
        }
        try await assertAccess(conversation, user: user, on: database)
        return conversation
    }

    static func participantUserIDs(conversationID: UUID, on database: any Database) async throws -> [UUID] {
        guard let conversation = try await Conversation.find(conversationID, on: database) else {
            throw Abort(.notFound, reason: "Conversation not found")
        }

        let trainer = try await conversation.$trainer.get(on: database)
        let client = try await conversation.$client.get(on: database)
        var ids: [UUID] = []
        if let trainerUserID = trainer.$user.id {
            ids.append(trainerUserID)
        }
        if let clientUserID = client.$user.id {
            ids.append(clientUserID)
        }
        return ids
    }

    static func messages(
        conversationID: UUID,
        before: Date?,
        limit: Int,
        viewer: User,
        on database: any Database
    ) async throws -> MessagesPageResponse {
        let conversation = try await requireConversation(conversationID, for: viewer, on: database)
        let viewerID = try viewer.requireID()
        let pageSize = min(max(limit, 1), 100)
        let conversationIDValue = try conversation.requireID()

        var query = Message.query(on: database)
            .filter(\.$conversation.$id == conversationIDValue)
            .sort(\.$createdAt, .descending)
            .limit(pageSize + 1)

        if let before {
            query = query.filter(\.$createdAt < before)
        }

        let rows = try await query.all()
        let hasMore = rows.count > pageSize
        let slice = hasMore ? Array(rows.prefix(pageSize)) : rows
        let delivered = try await markDelivered(
            conversationID: conversationIDValue,
            recipientUserID: viewerID,
            on: database
        )
        // Notify senders so their delivery ticks advance without requiring the
        // explicit /delivered endpoint (e.g. opening a thread marks delivered).
        for update in delivered {
            guard let senderID = update.$senderUser.id else { continue }
            let statusDTO = try MessageDTO(from: update, viewerUserID: senderID)
            await ChatHub.shared.send(
                to: senderID,
                event: ChatEvent(
                    type: "message.status",
                    message: statusDTO,
                    conversationID: conversationIDValue,
                    messageID: update.id
                )
            )
        }
        var dtos = try slice.map { try MessageDTO(from: $0, viewerUserID: viewerID) }
        for update in delivered {
            guard let id = update.id else { continue }
            if let index = dtos.firstIndex(where: { $0.id == id }) {
                dtos[index] = try MessageDTO(from: update, viewerUserID: viewerID)
            }
        }
        return MessagesPageResponse(messages: dtos.reversed(), hasMore: hasMore)
    }

    static func sendMessage(
        conversationID: UUID,
        payload: CreateMessageRequest,
        from user: User,
        on database: any Database,
        app: Application
    ) async throws -> MessageDTO {
        let conversation = try await requireConversation(conversationID, for: user, on: database)
        let userID = try user.requireID()
        let role = user.userRole ?? .client

        let kind = payload.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = payload.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kind.isEmpty else {
            throw Abort(.badRequest, reason: "Message kind is required")
        }

        var initialStatus = "sent"
        let participants = try await participantUserIDs(conversationID: conversationID, on: database)
        let recipients = participants.filter { $0 != userID }
        for recipient in recipients where await ChatHub.shared.isUserOnline(recipient) {
            initialStatus = "delivered"
            break
        }

        let message = Message(
            conversationID: try conversation.requireID(),
            senderUserID: userID,
            kind: kind,
            body: body,
            isOutgoing: role == .trainer,
            attachmentURL: payload.attachmentURL,
            status: initialStatus
        )
        try await message.save(on: database)

        conversation.lastMessagePreview = preview(for: kind, body: body)
        conversation.lastMessageAt = message.createdAt ?? .now
        conversation.lastActiveAt = .now

        // Sending restores the thread for the sender and surfaces it again for the recipient.
        conversation.restoreVisibility(for: role == .client ? .client : .trainer)
        if role == .trainer {
            conversation.clientIsUnread = true
            conversation.restoreVisibility(for: .client)
        } else {
            conversation.isUnread = true
            conversation.restoreVisibility(for: .trainer)
        }
        try await conversation.save(on: database)

        let dto = try MessageDTO(from: message, viewerUserID: userID)

        // Broadcast a recipient-scoped DTO so clients see the message as incoming.
        for recipient in recipients {
            let recipientDTO = try MessageDTO(from: message, viewerUserID: recipient)
            let event = ChatEvent(type: "message.new", message: recipientDTO, conversationID: conversationID)
            await ChatHub.shared.send(to: recipient, event: event)
        }

        let senderTitle = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (role == .trainer ? "Your trainer" : conversation.clientName)
            : user.displayName
        let pushBody = conversation.lastMessagePreview ?? "New message"

        for recipient in recipients {
            await MessagePushService.notifyNewMessage(
                to: recipient,
                title: senderTitle,
                body: pushBody,
                conversationID: conversationID,
                on: app
            )
        }

        return dto
    }

    static func markRead(conversationID: UUID, for user: User, on database: any Database) async throws -> ConversationDTO {
        let conversation = try await requireConversation(conversationID, for: user, on: database)
        let role = user.userRole ?? .client

        if role == .client {
            conversation.clientIsUnread = false
        } else {
            conversation.isUnread = false
        }
        try await conversation.save(on: database)

        let userID = try user.requireID()
        let readMessages = try await markReadReceipts(
            conversationID: conversationID,
            readerUserID: userID,
            on: database
        )
        for message in readMessages {
            guard let senderID = message.$senderUser.id else { continue }
            let messageDTO = try MessageDTO(from: message, viewerUserID: senderID)
            await ChatHub.shared.send(
                to: senderID,
                event: ChatEvent(
                    type: "message.status",
                    message: messageDTO,
                    conversationID: conversationID,
                    messageID: message.id
                )
            )
        }

        let dto = try await ConversationDTO.make(from: conversation, viewer: user, on: database)
        let participants = try await participantUserIDs(conversationID: conversationID, on: database)
        let others = participants.filter { $0 != userID }
        await ChatHub.shared.send(
            toUserIDs: others,
            event: ChatEvent(type: "conversation.read", conversationID: conversationID, userID: userID)
        )
        return dto
    }

    static func markDelivered(
        conversationID: UUID,
        for user: User,
        on database: any Database
    ) async throws -> [MessageDTO] {
        _ = try await requireConversation(conversationID, for: user, on: database)
        let userID = try user.requireID()
        let updated = try await markDelivered(
            conversationID: conversationID,
            recipientUserID: userID,
            on: database
        )
        var dtos: [MessageDTO] = []
        for message in updated {
            guard let senderID = message.$senderUser.id else { continue }
            let dto = try MessageDTO(from: message, viewerUserID: senderID)
            dtos.append(dto)
            await ChatHub.shared.send(
                to: senderID,
                event: ChatEvent(
                    type: "message.status",
                    message: dto,
                    conversationID: conversationID,
                    messageID: message.id
                )
            )
        }
        return dtos
    }

    static func setReaction(
        messageID: UUID,
        reaction: String?,
        for user: User,
        on database: any Database
    ) async throws -> MessageDTO {
        guard let message = try await Message.find(messageID, on: database) else {
            throw Abort(.notFound, reason: "Message not found")
        }

        let conversation = try await message.$conversation.get(on: database)
        try await assertAccess(conversation, user: user, on: database)

        message.reaction = reaction?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        try await message.save(on: database)

        let viewerID = try user.requireID()
        let dto = try MessageDTO(from: message, viewerUserID: viewerID)
        let conversationID = try conversation.requireID()
        let participants = try await participantUserIDs(conversationID: conversationID, on: database)
        await ChatHub.shared.send(
            toUserIDs: participants,
            event: ChatEvent(
                type: "message.reaction",
                conversationID: conversationID,
                messageID: messageID,
                reaction: message.reaction
            )
        )
        return dto
    }

    static func flushOfflineQueue(
        items: [QueuedMessageRequest],
        for user: User,
        on database: any Database,
        app: Application
    ) async throws -> [MessageDTO] {
        var sent: [MessageDTO] = []
        for item in items {
            let dto = try await sendMessage(
                conversationID: item.conversationID,
                payload: CreateMessageRequest(kind: item.kind, body: item.body, attachmentURL: item.attachmentURL),
                from: user,
                on: database,
                app: app
            )
            sent.append(dto)
        }
        return sent
    }

    private static func restoreIfHidden(
        _ conversation: Conversation,
        for role: UserRole,
        on database: any Database
    ) async throws -> Conversation {
        let viewerRole: UserRole = role == .client ? .client : .trainer
        guard conversation.isArchived(for: viewerRole) || conversation.isDeleted(for: viewerRole) else {
            return conversation
        }
        conversation.restoreVisibility(for: viewerRole)
        try await conversation.save(on: database)
        return conversation
    }

    private static func assertAccess(_ conversation: Conversation, user: User, on database: any Database) async throws {
        guard let role = user.userRole else {
            throw Abort(.forbidden)
        }

        if role == .admin { return }

        if role == .trainer {
            guard let trainer = try await Trainer.query(on: database)
                .filter(\.$user.$id == user.id!)
                .first(),
                conversation.$trainer.id == trainer.id else {
                throw Abort(.forbidden)
            }
            return
        }

        if role == .client {
            guard let client = try await Client.query(on: database)
                .filter(\.$user.$id == user.id!)
                .first(),
                conversation.$client.id == client.id else {
                throw Abort(.forbidden)
            }
            return
        }

        throw Abort(.forbidden)
    }

    private static func markDelivered(
        conversationID: UUID,
        recipientUserID: UUID,
        on database: any Database
    ) async throws -> [Message] {
        let rows = try await Message.query(on: database)
            .filter(\.$conversation.$id == conversationID)
            .filter(\.$status == "sent")
            .all()

        var updated: [Message] = []
        for message in rows {
            guard message.$senderUser.id != recipientUserID else { continue }
            message.status = "delivered"
            try await message.save(on: database)
            updated.append(message)
        }
        return updated
    }

    private static func markReadReceipts(
        conversationID: UUID,
        readerUserID: UUID,
        on database: any Database
    ) async throws -> [Message] {
        let rows = try await Message.query(on: database)
            .filter(\.$conversation.$id == conversationID)
            .filter(\.$status != "read")
            .all()

        var updated: [Message] = []
        for message in rows {
            guard let senderID = message.$senderUser.id, senderID != readerUserID else { continue }
            message.status = "read"
            try await message.save(on: database)
            updated.append(message)
        }
        return updated
    }

    private static func preview(for kind: String, body: String) -> String {
        switch kind {
        case "photo": return "📷 Photo"
        case "video": return "🎥 Video message"
        case "voice": return "🎤 Voice message"
        case "file": return body.isEmpty ? "📎 File" : "📎 \(body)"
        default: return body.isEmpty ? "Message" : body
        }
    }
}

struct QueuedMessageRequest: Content {
    let conversationID: UUID
    let kind: String
    let body: String
    let attachmentURL: String?
}

struct FlushOfflineQueueRequest: Content {
    let messages: [QueuedMessageRequest]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
