import Fluent
import Vapor

enum MessagePushService {
    static func registerToken(_ token: String, platform: String, for user: User, on database: any Database) async throws {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw Abort(.badRequest, reason: "Push token is required")
        }

        if let existing = try await PushDeviceToken.query(on: database)
            .filter(\.$token == normalized)
            .first() {
            existing.$user.id = try user.requireID()
            existing.platform = platform
            existing.invalidatedAt = nil
            existing.lastError = nil
            try await existing.save(on: database)
            return
        }

        let record = PushDeviceToken(
            userID: try user.requireID(),
            token: normalized,
            platform: platform
        )
        try await record.save(on: database)
    }

    static func notifyNewMessage(
        to userID: UUID,
        title: String,
        body: String,
        conversationID: UUID,
        on app: Application
    ) async {
        let isOnline = await ChatHub.shared.isUserOnline(userID)
        if isOnline {
            let event = ChatEvent(
                type: "push.notification",
                conversationID: conversationID,
                preview: body
            )
            await ChatHub.shared.send(to: userID, event: event)
            return
        }

        let tokens = (try? await PushTokenService.activeTokens(for: userID, on: app.db)) ?? []
        guard !tokens.isEmpty else {
            app.logger.info("Push skipped for user \(userID) — no active device tokens")
            return
        }

        for record in tokens {
            _ = try? await NotificationDeliveryService.sendPushAlert(
                userID: userID,
                deviceToken: record.token,
                title: title,
                body: body,
                kind: .chatMessage,
                conversationID: conversationID,
                sessionID: nil,
                on: app.db,
                app: app
            )
        }
    }
}
