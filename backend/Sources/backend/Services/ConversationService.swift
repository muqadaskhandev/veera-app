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
                .sort(\.$lastMessageAt, .descending)
                .all()
            var result: [ConversationDTO] = []
            for row in rows {
                result.append(try await ConversationDTO.make(from: row, viewer: user, on: database))
            }
            return result

        case .admin:
            let rows = try await Conversation.query(on: database)
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

        guard let trainer = try await Trainer.query(on: database)
            .filter(\.$user.$id == trainerUser.id!)
            .first() else {
            throw Abort(.notFound, reason: "Trainer profile not found")
        }

        guard let client = try await Client.find(clientID, on: database) else {
            throw Abort(.notFound, reason: "Client not found")
        }

        if trainerUser.userRole != .admin, client.$trainer.id != trainer.id {
            throw Abort(.forbidden)
        }

        if let existing = try await Conversation.query(on: database)
            .filter(\.$trainer.$id == client.$trainer.id)
            .filter(\.$client.$id == clientID)
            .first() {
            return existing
        }

        let conversation = Conversation(
            trainerID: client.$trainer.id,
            clientID: clientID,
            clientName: client.name,
            initials: client.initials
        )
        try await conversation.save(on: database)
        return conversation
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
            return existing
        }

        let conversation = Conversation(
            trainerID: client.$trainer.id,
            clientID: try client.requireID(),
            clientName: client.name,
            initials: client.initials
        )
        try await conversation.save(on: database)
        return conversation
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
        let dtos = try slice.map { try MessageDTO(from: $0, viewerUserID: viewerID) }
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

        let message = Message(
            conversationID: try conversation.requireID(),
            senderUserID: userID,
            kind: kind,
            body: body,
            isOutgoing: role == .trainer,
            attachmentURL: payload.attachmentURL,
            status: "sent"
        )
        try await message.save(on: database)

        conversation.lastMessagePreview = preview(for: kind, body: body)
        conversation.lastMessageAt = message.createdAt ?? .now
        conversation.lastActiveAt = .now

        if role == .trainer {
            conversation.clientIsUnread = true
        } else {
            conversation.isUnread = true
        }
        try await conversation.save(on: database)

        let dto = try MessageDTO(from: message, viewerUserID: userID)
        let participants = try await participantUserIDs(conversationID: conversationID, on: database)
        let recipients = participants.filter { $0 != userID }

        let event = ChatEvent(type: "message.new", message: dto, conversationID: conversationID)
        await ChatHub.shared.send(toUserIDs: recipients, event: event)

        for recipient in recipients {
            await MessagePushService.notifyNewMessage(
                to: recipient,
                title: conversation.clientName,
                body: conversation.lastMessagePreview ?? "New message",
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

        let dto = try await ConversationDTO.make(from: conversation, viewer: user, on: database)
        let userID = try user.requireID()
        let participants = try await participantUserIDs(conversationID: conversationID, on: database)
        let others = participants.filter { $0 != userID }
        await ChatHub.shared.send(
            toUserIDs: others,
            event: ChatEvent(type: "conversation.read", conversationID: conversationID, userID: userID)
        )
        return dto
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

    private static func preview(for kind: String, body: String) -> String {
        switch kind {
        case "photo": return "📷 Photo"
        case "video": return "🎥 Video message"
        case "voice": return "🎤 Voice message"
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
