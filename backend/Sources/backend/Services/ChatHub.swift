import Fluent
import JWT
import NIOWebSocket
import Vapor

struct ChatEvent: Codable, Sendable {
    let type: String
    var message: MessageDTO?
    var conversationID: UUID?
    var messageID: UUID?
    var reaction: String?
    var userID: UUID?
    var isTyping: Bool?
    var preview: String?
    var isOnline: Bool?
    var lastSeen: Date?
    var presence: [PresenceStateDTO]?
}

/// Tracks live WebSocket connections and broadcasts chat events.
actor ChatHub {
    static let shared = ChatHub()

    private struct Connection {
        let id: UUID
        let userID: UUID
        let socket: WebSocket
    }

    private var connections: [UUID: Connection] = [:]
    private var userConnectionIDs: [UUID: Set<UUID>] = [:]

    func connect(userID: UUID, socket: WebSocket) -> UUID {
        let id = UUID()
        connections[id] = Connection(id: id, userID: userID, socket: socket)
        userConnectionIDs[userID, default: []].insert(id)
        return id
    }

    func disconnect(connectionID: UUID, on database: (any Database)? = nil) async {
        guard let connection = connections.removeValue(forKey: connectionID) else { return }
        userConnectionIDs[connection.userID]?.remove(connectionID)
        let wentOffline = userConnectionIDs[connection.userID]?.isEmpty ?? true
        if userConnectionIDs[connection.userID]?.isEmpty == true {
            userConnectionIDs.removeValue(forKey: connection.userID)
        }
        if wentOffline, let database {
            await PresenceService.userDisconnected(userID: connection.userID, on: database)
        }
    }

    func isUserOnline(_ userID: UUID) -> Bool {
        !(userConnectionIDs[userID]?.isEmpty ?? true)
    }

    func send(to userID: UUID, event: ChatEvent) async {
        guard let ids = userConnectionIDs[userID], !ids.isEmpty else { return }
        guard let payload = try? JSONEncoder().encode(event),
              let text = String(data: payload, encoding: .utf8) else { return }

        for connectionID in ids {
            guard let connection = connections[connectionID] else { continue }
            try? await connection.socket.send(text)
        }
    }

    func send(toUserIDs: [UUID], event: ChatEvent) async {
        for userID in Set(toUserIDs) {
            await send(to: userID, event: event)
        }
    }
}

enum ChatWebSocketHandler {
    static func handle(req: Request, socket: WebSocket) async {
        guard let token = req.query[String.self, at: "token"], !token.isEmpty else {
            try? await socket.close(code: .policyViolation)
            return
        }

        let user: User
        do {
            let payload = try req.jwt.verify(token, as: AccessTokenPayload.self)
            guard let userID = UUID(uuidString: payload.subject.value),
                  let loaded = try await User.find(userID, on: req.db),
                  loaded.isActive else {
                try await socket.close(code: .policyViolation)
                return
            }
            user = loaded
        } catch {
            try? await socket.close(code: .policyViolation)
            return
        }

        let userID: UUID
        do {
            userID = try user.requireID()
        } catch {
            try? await socket.close(code: .policyViolation)
            return
        }

        let connectionID = await ChatHub.shared.connect(userID: userID, socket: socket)
        await PresenceService.userConnected(userID: userID, on: req.db)

        socket.onText { _, text in
            Task {
                try? await handleIncoming(text: text, from: user, on: req)
            }
        }

        socket.onClose.whenComplete { _ in
            Task { await ChatHub.shared.disconnect(connectionID: connectionID, on: req.db) }
        }
    }

    private static func handleIncoming(text: String, from user: User, on req: Request) async throws {
        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(IncomingChatCommand.self, from: data) else {
            return
        }

        switch payload.type {
        case "typing.start", "typing.stop":
            guard let conversationID = payload.conversationID else { return }
            let participants = try await ConversationService.participantUserIDs(
                conversationID: conversationID,
                on: req.db
            )
            let senderID = try user.requireID()
            let others = participants.filter { $0 != senderID }
            let event = ChatEvent(
                type: payload.type,
                conversationID: conversationID,
                userID: senderID,
                isTyping: payload.type == "typing.start"
            )
            await ChatHub.shared.send(toUserIDs: others, event: event)
        default:
            break
        }
    }
}

private struct IncomingChatCommand: Decodable {
    let type: String
    let conversationID: UUID?
}
