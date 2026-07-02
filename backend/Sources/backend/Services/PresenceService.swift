import Fluent
import Vapor

struct PresenceStateDTO: Content, Codable, Sendable {
    let userID: UUID
    let isOnline: Bool
    let lastSeen: Date?
}

enum PresenceService {
    static func state(for userID: UUID, on database: any Database) async -> PresenceStateDTO {
        let isOnline = await ChatHub.shared.isUserOnline(userID)
        let lastSeen = try? await User.find(userID, on: database)?.lastSeenAt
        return PresenceStateDTO(userID: userID, isOnline: isOnline, lastSeen: lastSeen)
    }

    static func otherParticipantUserID(
        in conversation: Conversation,
        viewerID: UUID,
        on database: any Database
    ) async throws -> UUID? {
        let trainer = try await conversation.$trainer.get(on: database)
        let client = try await conversation.$client.get(on: database)
        if trainer.$user.id == viewerID { return client.$user.id }
        if client.$user.id == viewerID { return trainer.$user.id }
        return nil
    }

    static func conversationPartnerUserIDs(for userID: UUID, on database: any Database) async throws -> Set<UUID> {
        var partners = Set<UUID>()

        if let trainer = try await Trainer.query(on: database)
            .filter(\.$user.$id == userID)
            .first() {
            let conversations = try await Conversation.query(on: database)
                .filter(\.$trainer.$id == trainer.id!)
                .all()
            for conversation in conversations {
                let client = try await conversation.$client.get(on: database)
                if let clientUserID = client.$user.id {
                    partners.insert(clientUserID)
                }
            }
        }

        if let client = try await Client.query(on: database)
            .filter(\.$user.$id == userID)
            .first() {
            let conversations = try await Conversation.query(on: database)
                .filter(\.$client.$id == client.id!)
                .all()
            for conversation in conversations {
                let trainer = try await conversation.$trainer.get(on: database)
                if let trainerUserID = trainer.$user.id {
                    partners.insert(trainerUserID)
                }
            }
        }

        return partners
    }

    static func markLastSeen(userID: UUID, on database: any Database) async {
        guard let user = try? await User.find(userID, on: database) else { return }
        user.lastSeenAt = .now
        try? await user.save(on: database)
    }

    static func sendSnapshot(to userID: UUID, on database: any Database) async {
        guard let partners = try? await conversationPartnerUserIDs(for: userID, on: database),
              !partners.isEmpty else { return }

        var states: [PresenceStateDTO] = []
        for partnerID in partners {
            states.append(await state(for: partnerID, on: database))
        }

        let event = ChatEvent(type: "presence.snapshot", presence: states)
        await ChatHub.shared.send(to: userID, event: event)
    }

    static func broadcastPresence(
        userID: UUID,
        isOnline: Bool,
        on database: any Database
    ) async {
        guard let partners = try? await conversationPartnerUserIDs(for: userID, on: database),
              !partners.isEmpty else { return }

        let lastSeen: Date?
        if isOnline {
            lastSeen = nil
        } else {
            lastSeen = try? await User.find(userID, on: database)?.lastSeenAt
        }

        let event = ChatEvent(
            type: "presence.update",
            userID: userID,
            isOnline: isOnline,
            lastSeen: lastSeen
        )
        await ChatHub.shared.send(toUserIDs: Array(partners), event: event)
    }

    static func userConnected(userID: UUID, on database: any Database) async {
        await broadcastPresence(userID: userID, isOnline: true, on: database)
        await sendSnapshot(to: userID, on: database)
    }

    static func userDisconnected(userID: UUID, on database: any Database) async {
        await markLastSeen(userID: userID, on: database)
        await broadcastPresence(userID: userID, isOnline: false, on: database)
    }
}
