import Fluent
import Vapor

struct ConversationController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let chat = routes.grouped("api", "conversations")
            .grouped(JWTAuthMiddleware())

        chat.get(use: index)
        chat.post("mine", use: getOrCreateMine)
        chat.post("for-client", ":clientID", use: getOrCreateForClient)
        chat.get(":conversationID", use: show)
        chat.get(":conversationID", "messages", use: messages)
        chat.post(":conversationID", "messages", use: send)
        chat.patch(":conversationID", "read", use: markRead)
        chat.on(.POST, ":conversationID", "attachments", body: .collect(maxSize: "26mb"), use: uploadAttachment)
        chat.get("attachments", ":filename", use: serveAttachment)

        let messages = routes.grouped("api", "messages")
            .grouped(JWTAuthMiddleware())
        messages.patch(":messageID", "reaction", use: setReaction)

        let devices = routes.grouped("api", "devices")
            .grouped(JWTAuthMiddleware())
        devices.post("push-token", use: registerPushToken)

        let offline = routes.grouped("api", "chat")
            .grouped(JWTAuthMiddleware())
        offline.post("offline-queue", use: flushOfflineQueue)
    }

    @Sendable
    func index(req: Request) async throws -> [ConversationDTO] {
        let user = try req.auth.require(User.self)
        return try await ConversationService.list(for: user, on: req.db)
    }

    @Sendable
    func getOrCreateMine(req: Request) async throws -> ConversationDTO {
        let user = try req.auth.require(User.self)
        let conversation = try await ConversationService.getOrCreateForCurrentClient(user: user, on: req.db)
        return try await ConversationDTO.make(from: conversation, viewer: user, on: req.db)
    }

    @Sendable
    func getOrCreateForClient(req: Request) async throws -> ConversationDTO {
        let user = try req.auth.require(User.self)
        guard let clientID = req.parameters.get("clientID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid client ID")
        }
        let conversation = try await ConversationService.getOrCreate(
            forClientID: clientID,
            trainerUser: user,
            on: req.db
        )
        return try await ConversationDTO.make(from: conversation, viewer: user, on: req.db)
    }

    @Sendable
    func show(req: Request) async throws -> ConversationDetailResponse {
        let user = try req.auth.require(User.self)
        guard let conversationID = req.parameters.get("conversationID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid conversation ID")
        }
        let conversation = try await ConversationService.requireConversation(
            conversationID,
            for: user,
            on: req.db
        )
        let includeMessages = req.query[Int.self, at: "includeMessages"] ?? 50
        let page = try await ConversationService.messages(
            conversationID: conversationID,
            before: nil,
            limit: includeMessages,
            viewer: user,
            on: req.db
        )
        return ConversationDetailResponse(
            conversation: try await ConversationDTO.make(from: conversation, viewer: user, on: req.db),
            messages: page.messages
        )
    }

    @Sendable
    func messages(req: Request) async throws -> MessagesPageResponse {
        let user = try req.auth.require(User.self)
        guard let conversationID = req.parameters.get("conversationID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid conversation ID")
        }
        let before = req.query[Date.self, at: "before"]
        let limit = req.query[Int.self, at: "limit"] ?? 50
        return try await ConversationService.messages(
            conversationID: conversationID,
            before: before,
            limit: limit,
            viewer: user,
            on: req.db
        )
    }

    @Sendable
    func send(req: Request) async throws -> MessageDTO {
        let user = try req.auth.require(User.self)
        guard let conversationID = req.parameters.get("conversationID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid conversation ID")
        }
        let payload = try req.content.decode(CreateMessageRequest.self)
        return try await ConversationService.sendMessage(
            conversationID: conversationID,
            payload: payload,
            from: user,
            on: req.db,
            app: req.application
        )
    }

    @Sendable
    func markRead(req: Request) async throws -> ConversationDTO {
        let user = try req.auth.require(User.self)
        guard let conversationID = req.parameters.get("conversationID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid conversation ID")
        }
        return try await ConversationService.markRead(
            conversationID: conversationID,
            for: user,
            on: req.db
        )
    }

    @Sendable
    func setReaction(req: Request) async throws -> MessageDTO {
        let user = try req.auth.require(User.self)
        guard let messageID = req.parameters.get("messageID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid message ID")
        }
        let payload = try req.content.decode(UpdateMessageReactionRequest.self)
        return try await ConversationService.setReaction(
            messageID: messageID,
            reaction: payload.reaction,
            for: user,
            on: req.db
        )
    }

    @Sendable
    func uploadAttachment(req: Request) async throws -> AttachmentUploadResponse {
        let user = try req.auth.require(User.self)
        guard let conversationID = req.parameters.get("conversationID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid conversation ID")
        }
        _ = try await ConversationService.requireConversation(conversationID, for: user, on: req.db)

        struct Upload: Content {
            var file: File
        }
        let upload = try req.content.decode(Upload.self)
        let url = try await MessageMediaService.save(file: upload.file, on: req.application)
        return AttachmentUploadResponse(attachmentURL: url)
    }

    @Sendable
    func serveAttachment(req: Request) async throws -> Response {
        guard let filename = req.parameters.get("filename") else {
            throw Abort(.badRequest)
        }
        guard let path = MessageMediaService.resolvePath(filename: filename, on: req.application) else {
            throw Abort(.notFound)
        }
        return try await req.fileio.asyncStreamFile(at: path)
    }

    @Sendable
    func registerPushToken(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(RegisterPushTokenRequest.self)
        try await MessagePushService.registerToken(
            payload.token,
            platform: payload.platform ?? "ios",
            for: user,
            on: req.db
        )
        return .ok
    }

    @Sendable
    func flushOfflineQueue(req: Request) async throws -> [MessageDTO] {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(FlushOfflineQueueRequest.self)
        return try await ConversationService.flushOfflineQueue(
            items: payload.messages,
            for: user,
            on: req.db,
            app: req.application
        )
    }
}

struct AttachmentUploadResponse: Content {
    let attachmentURL: String
}
