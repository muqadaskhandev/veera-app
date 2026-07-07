import Fluent
import Foundation
import Vapor

enum SessionReminderScheduler {
    static func reschedule(for session: Session, on database: any Database, app: Application) async throws {
        try await cancel(for: session, on: database)
        guard !session.isCompleted, !session.isSkipped, session.accent != "personal" else { return }
        guard let sessionID = session.id else { return }

        let recipients = try await reminderRecipients(for: session, on: database)
        for (user, prefs, phone) in recipients {
            let minutes = max(5, prefs.reminderMinutesBefore)
            let fireAt = session.scheduledAt.addingTimeInterval(-Double(minutes * 60))
            guard fireAt > Date() else { continue }

            let pushReminder = ScheduledReminder(sessionID: sessionID, userID: user.id!, channel: "push", fireAt: fireAt)
            try await pushReminder.save(on: database)

            if prefs.smsEnabled, !phone.isEmpty, TwilioService.isConfigured() {
                let smsReminder = ScheduledReminder(sessionID: sessionID, userID: user.id!, channel: "sms", fireAt: fireAt)
                try await smsReminder.save(on: database)
            }
        }
    }

    static func cancel(for session: Session, on database: any Database) async throws {
        guard let sessionID = session.id else { return }
        try await ScheduledReminder.query(on: database)
            .filter(\.$session.$id == sessionID)
            .filter(\.$sentAt == nil)
            .delete()
    }

    static func processDueReminders(on database: any Database, app: Application) async {
        let due = (try? await ScheduledReminder.query(on: database)
            .filter(\.$fireAt <= Date())
            .filter(\.$sentAt == nil)
            .with(\.$session)
            .with(\.$user)
            .all()) ?? []

        for reminder in due {
            let session = reminder.session
            let prefs = (try? await NotificationService.preferences(for: reminder.user, on: database))
                ?? NotificationPreferences(userID: reminder.user.id!)
            guard prefs.notifySchedule else {
                reminder.sentAt = Date()
                try? await reminder.save(on: database)
                continue
            }

            let timeLabel = SessionService.timeLabel(session.scheduledAt)
            let title = "\(session.focus) with \(session.clientName)"
            let body = "Starts at \(timeLabel)\(session.location.isEmpty ? "" : " · \(session.location)")"

            switch reminder.channel {
            case "push":
                await sendPush(
                    to: reminder.user,
                    title: title,
                    body: body,
                    sessionID: session.id!,
                    scheduledReminderID: reminder.id,
                    on: database,
                    app: app
                )
            case "sms":
                if prefs.smsEnabled,
                   let clientID = session.$client.id,
                   let client = try? await Client.find(clientID, on: database),
                   !client.phone.isEmpty {
                    let smsBody = TwilioService.sessionReminderMessage(
                        clientName: session.clientName,
                        focus: session.focus,
                        timeLabel: timeLabel,
                        location: session.location
                    )
                    _ = try? await NotificationDeliveryService.sendSMS(
                        userID: reminder.user.id,
                        phone: client.phone,
                        title: title,
                        body: smsBody,
                        kind: .sessionReminder,
                        scheduledReminderID: reminder.id,
                        on: database,
                        app: app
                    )
                }
            default:
                break
            }

            reminder.sentAt = Date()
            try? await reminder.save(on: database)

            if let userID = reminder.user.id {
                await UserNotificationDeliveryService.deliver(
                    to: userID,
                    topic: .schedule,
                    category: "reminder",
                    title: title,
                    body: body,
                    pushKind: .sessionReminder,
                    sessionID: session.id,
                    includePush: false,
                    on: database,
                    app: app
                )
            }
        }
    }

    private static func sendPush(
        to user: User,
        title: String,
        body: String,
        sessionID: UUID,
        scheduledReminderID: UUID?,
        on database: any Database,
        app: Application
    ) async {
        guard let userID = user.id else { return }
        let tokens = (try? await PushTokenService.activeTokens(for: userID, on: database)) ?? []

        for token in tokens {
            var outbox = NotificationOutbox(
                userID: userID,
                channel: NotificationChannel.push.rawValue,
                kind: NotificationDeliveryKind.sessionReminder.rawValue,
                recipient: token.token,
                title: title,
                body: body,
                metadataJSON: encodeSessionMetadata(sessionID: sessionID),
                scheduledReminderID: scheduledReminderID
            )
            try? await outbox.save(on: database)
            await NotificationDeliveryService.deliver(outbox, on: database, app: app)
        }
    }

    private static func encodeSessionMetadata(sessionID: UUID) -> String? {
        struct Payload: Codable { let sessionID: UUID }
        guard let data = try? JSONEncoder().encode(Payload(sessionID: sessionID)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func reminderRecipients(
        for session: Session,
        on database: any Database
    ) async throws -> [(User, NotificationPreferences, String)] {
        var results: [(User, NotificationPreferences, String)] = []

        if let trainer = try await Trainer.find(session.$trainer.id, on: database),
           let trainerUser = try await trainer.$user.get(on: database) {
            let prefs = try await NotificationService.preferences(for: trainerUser, on: database)
            results.append((trainerUser, prefs, ""))
        }

        if let clientID = session.$client.id,
           let client = try await Client.find(clientID, on: database),
           let clientUserID = client.$user.id,
           let clientUser = try await User.find(clientUserID, on: database) {
            let prefs = try await NotificationService.preferences(for: clientUser, on: database)
            results.append((clientUser, prefs, client.phone))
        }

        return results
    }
}

struct ReminderPollingService: LifecycleHandler {
    func didBoot(_ application: Application) throws {
        application.eventLoopGroup.next().scheduleRepeatedTask(initialDelay: .seconds(15), delay: .seconds(60)) { _ in
            Task {
                await SessionReminderScheduler.processDueReminders(on: application.db, app: application)
                await SubscriptionExpiryScheduler.processExpiredSubscriptions(on: application.db, app: application)
                await NotificationDeliveryService.processRetries(on: application.db, app: application)
            }
        }
    }
}
