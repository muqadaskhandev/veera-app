import Fluent
import Foundation
import Vapor

enum NotificationTopic {
    case money
    case activity
    case schedule
    case message
}

enum UserNotificationDeliveryService {
    static func deliver(
        to user: User,
        topic: NotificationTopic,
        category: String,
        title: String,
        body: String,
        pushKind: NotificationDeliveryKind,
        metadataJSON: String? = nil,
        conversationID: UUID? = nil,
        sessionID: UUID? = nil,
        includePush: Bool = true,
        on database: any Database,
        app: Application
    ) async {
        guard let userID = user.id else { return }
        await deliver(
            to: userID,
            topic: topic,
            category: category,
            title: title,
            body: body,
            pushKind: pushKind,
            metadataJSON: metadataJSON,
            conversationID: conversationID,
            sessionID: sessionID,
            includePush: includePush,
            on: database,
            app: app
        )
    }

    static func deliver(
        to userID: UUID,
        topic: NotificationTopic,
        category: String,
        title: String,
        body: String,
        pushKind: NotificationDeliveryKind,
        metadataJSON: String? = nil,
        conversationID: UUID? = nil,
        sessionID: UUID? = nil,
        includePush: Bool = true,
        on database: any Database,
        app: Application
    ) async {
        guard let user = try? await User.find(userID, on: database), user.isActive else { return }

        let prefs = (try? await NotificationService.preferences(for: user, on: database))
            ?? NotificationPreferences(userID: userID)

        guard prefs.notificationsEnabled else { return }
        guard topicAllowed(topic, prefs: prefs) else { return }

        _ = try? await NotificationService.create(
            userID: userID,
            category: category,
            title: title,
            body: body,
            metadataJSON: metadataJSON,
            on: database
        )

        guard includePush, !isQuietHours(prefs) else { return }

        let tokens = (try? await PushTokenService.activeTokens(for: userID, on: database)) ?? []
        guard !tokens.isEmpty else { return }

        for token in tokens {
            _ = try? await NotificationDeliveryService.sendPushAlert(
                userID: userID,
                deviceToken: token.token,
                title: title,
                body: body,
                kind: pushKind,
                conversationID: conversationID,
                sessionID: sessionID,
                on: database,
                app: app
            )
        }
    }

    private static func topicAllowed(_ topic: NotificationTopic, prefs: NotificationPreferences) -> Bool {
        switch topic {
        case .money: return prefs.notifyMoney
        case .activity: return prefs.notifyActivity
        case .schedule: return prefs.notifySchedule
        case .message: return prefs.notifyMessages
        }
    }

    private static func isQuietHours(_ prefs: NotificationPreferences) -> Bool {
        guard prefs.quietHoursEnabled else { return false }
        let calendar = Calendar.current
        let now = calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date())
        let start = prefs.quietStartMinutes
        let end = prefs.quietEndMinutes
        if start <= end {
            return now >= start && now < end
        }
        return now >= start || now < end
    }
}
