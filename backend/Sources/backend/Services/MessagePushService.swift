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

        let tokens = try? await PushDeviceToken.query(on: app.db)
            .filter(\.$user.$id == userID)
            .all()

        guard let tokens, !tokens.isEmpty else {
            app.logger.info("Push skipped for user \(userID) — no device tokens registered")
            return
        }

        for record in tokens {
            await APNsService.sendAlert(
                to: record.token,
                title: title,
                body: body,
                conversationID: conversationID,
                on: app
            )
        }
    }
}
