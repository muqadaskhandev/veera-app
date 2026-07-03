import Fluent
import Foundation
import Vapor

enum NotificationService {
    static func preferences(for user: User, on database: any Database) async throws -> NotificationPreferences {
        guard let userID = user.id else { throw Abort(.internalServerError) }
        if let existing = try await NotificationPreferences.query(on: database)
            .filter(\.$user.$id == userID)
            .first() {
            return existing
        }
        let prefs = NotificationPreferences(userID: userID)
        try await prefs.save(on: database)
        return prefs
    }

    static func updatePreferences(
        for user: User,
        payload: UpdateNotificationPreferencesRequest,
        on database: any Database
    ) async throws -> NotificationPreferencesDTO {
        let prefs = try await preferences(for: user, on: database)
        if let notifySchedule = payload.notifySchedule { prefs.notifySchedule = notifySchedule }
        if let notifyMessages = payload.notifyMessages { prefs.notifyMessages = notifyMessages }
        if let notifyActivity = payload.notifyActivity { prefs.notifyActivity = notifyActivity }
        if let smsEnabled = payload.smsEnabled { prefs.smsEnabled = smsEnabled }
        if let reminderMinutesBefore = payload.reminderMinutesBefore {
            prefs.reminderMinutesBefore = max(5, min(reminderMinutesBefore, 24 * 60))
        }
        try await prefs.save(on: database)
        return NotificationPreferencesDTO(from: prefs)
    }

    static func list(for user: User, on database: any Database) async throws -> [UserNotificationDTO] {
        guard let userID = user.id else { return [] }
        return try await UserNotification.query(on: database)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .descending)
            .limit(100)
            .all()
            .map { try UserNotificationDTO(from: $0) }
    }

    static func markRead(notificationID: UUID, for user: User, on database: any Database) async throws {
        guard let userID = user.id,
              let notification = try await UserNotification.find(notificationID, on: database),
              notification.$user.id == userID else {
            throw Abort(.notFound)
        }
        notification.readAt = Date()
        try await notification.save(on: database)
    }

    static func markAllRead(for user: User, on database: any Database) async throws {
        guard let userID = user.id else { return }
        let unread = try await UserNotification.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$readAt == nil)
            .all()
        for notification in unread {
            notification.readAt = Date()
            try await notification.save(on: database)
        }
    }

    @discardableResult
    static func create(
        userID: UUID,
        category: String,
        title: String,
        body: String,
        metadataJSON: String? = nil,
        on database: any Database
    ) async throws -> UserNotification {
        let notification = UserNotification(
            userID: userID,
            category: category,
            title: title,
            body: body,
            metadataJSON: metadataJSON
        )
        try await notification.save(on: database)
        return notification
    }
}
