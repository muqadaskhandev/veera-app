import Fluent
import Foundation
import Vapor

struct APNsSendResult {
    let accepted: Bool
    let statusCode: Int
    let reason: String?

    var invalidDeviceToken: Bool {
        if statusCode == 410 { return true }
        guard let reason else { return false }
        let normalized = reason.lowercased()
        return normalized.contains("baddevicetoken")
            || normalized.contains("unregistered")
            || normalized.contains("devicetokennotfortopic")
    }
}

struct TwilioSendResult {
    let success: Bool
    let messageSID: String?
    let statusCode: Int
    let error: String?
}

enum NotificationDeliveryService {
    private static let retryDelays: [TimeInterval] = [300, 900, 3600]

    // MARK: - Enqueue + send

    @discardableResult
    static func sendPushAlert(
        userID: UUID,
        deviceToken: String,
        title: String,
        body: String,
        kind: NotificationDeliveryKind,
        conversationID: UUID?,
        sessionID: UUID?,
        on database: any Database,
        app: Application
    ) async throws -> NotificationOutbox {
        let metadata = encodeMetadata(conversationID: conversationID, sessionID: sessionID)
        let outbox = NotificationOutbox(
            userID: userID,
            channel: NotificationChannel.push.rawValue,
            kind: kind.rawValue,
            recipient: deviceToken,
            title: title,
            body: body,
            metadataJSON: metadata
        )
        try await outbox.save(on: database)
        await deliver(outbox, on: database, app: app)
        return outbox
    }

    @discardableResult
    static func sendSMS(
        userID: UUID?,
        phone: String,
        title: String,
        body: String,
        kind: NotificationDeliveryKind,
        scheduledReminderID: UUID? = nil,
        on database: any Database,
        app: Application
    ) async throws -> NotificationOutbox {
        let outbox = NotificationOutbox(
            userID: userID,
            channel: NotificationChannel.sms.rawValue,
            kind: kind.rawValue,
            recipient: phone,
            title: title,
            body: body,
            scheduledReminderID: scheduledReminderID
        )
        try await outbox.save(on: database)
        await deliver(outbox, on: database, app: app)
        return outbox
    }

    static func deliver(_ outbox: NotificationOutbox, on database: any Database, app: Application) async {
        guard let outboxID = outbox.id else { return }
        guard outbox.status == NotificationDeliveryStatus.pending.rawValue
            || outbox.status == NotificationDeliveryStatus.failed.rawValue else {
            return
        }

        outbox.attemptCount += 1

        switch outbox.channel {
        case NotificationChannel.push.rawValue:
            await deliverPush(outbox, on: database, app: app)
        case NotificationChannel.sms.rawValue:
            await deliverSMS(outbox, on: database, app: app)
        default:
            await markFailed(outbox, error: "Unknown channel", retry: false, on: database)
        }

        try? await outbox.save(on: database)
        app.logger.debug("Notification outbox \(outboxID) -> \(outbox.status)")
    }

    // MARK: - Retry + webhooks

    static func processRetries(on database: any Database, app: Application) async {
        let candidates = (try? await NotificationOutbox.query(on: database)
            .filter(\.$status == NotificationDeliveryStatus.failed.rawValue)
            .filter(\.$nextRetryAt <= Date())
            .all()) ?? []

        for outbox in candidates where outbox.attemptCount < outbox.maxAttempts {
            outbox.status = NotificationDeliveryStatus.pending.rawValue
            try? await outbox.save(on: database)
            await deliver(outbox, on: database, app: app)
        }

        await PushTokenService.purgeStaleInvalidTokens(on: database)
    }

    static func applyTwilioStatus(
        messageSID: String,
        status: String,
        errorMessage: String?,
        on database: any Database,
        app: Application
    ) async {
        guard let outbox = try? await NotificationOutbox.query(on: database)
            .filter(\.$externalID == messageSID)
            .first() else {
            app.logger.warning("Twilio webhook for unknown MessageSid \(messageSID)")
            return
        }

        switch status.lowercased() {
        case "delivered", "read":
            outbox.status = NotificationDeliveryStatus.delivered.rawValue
            outbox.deliveredAt = Date()
            outbox.lastError = nil
        case "undelivered", "failed":
            outbox.status = NotificationDeliveryStatus.failed.rawValue
            outbox.failedAt = Date()
            outbox.lastError = errorMessage ?? status
            scheduleRetryIfNeeded(outbox)
        case "sent", "sending", "queued":
            if outbox.status == NotificationDeliveryStatus.pending.rawValue {
                outbox.status = NotificationDeliveryStatus.sent.rawValue
                outbox.sentAt = outbox.sentAt ?? Date()
            }
        default:
            break
        }

        try? await outbox.save(on: database)
    }

    static func retry(outboxID: UUID, on database: any Database, app: Application) async throws -> NotificationOutboxDTO {
        guard let outbox = try await NotificationOutbox.find(outboxID, on: database) else {
            throw Abort(.notFound, reason: "Delivery not found")
        }
        guard outbox.attemptCount < outbox.maxAttempts else {
            throw Abort(.badRequest, reason: "Maximum retry attempts reached")
        }
        outbox.status = NotificationDeliveryStatus.pending.rawValue
        outbox.nextRetryAt = nil
        try await outbox.save(on: database)
        await deliver(outbox, on: database, app: app)
        return try NotificationOutboxDTO(from: outbox)
    }

    // MARK: - Admin

    static func adminList(
        status: String?,
        channel: String?,
        limit: Int,
        on database: any Database
    ) async throws -> [NotificationOutboxDTO] {
        var query = NotificationOutbox.query(on: database).sort(\.$createdAt, .descending)
        if let status, !status.isEmpty {
            query = query.filter(\.$status == status)
        }
        if let channel, !channel.isEmpty {
            query = query.filter(\.$channel == channel)
        }
        return try await query.limit(min(max(limit, 1), 200)).all().map { try NotificationOutboxDTO(from: $0) }
    }

    static func adminSummary(on database: any Database) async throws -> DeliverySummaryDTO {
        let all = try await NotificationOutbox.query(on: database).all()
        let since = Date().addingTimeInterval(-24 * 3600)
        let recent = all.filter { ($0.createdAt ?? .distantPast) >= since }

        func count(_ status: NotificationDeliveryStatus, in rows: [NotificationOutbox]) -> Int {
            rows.filter { $0.status == status.rawValue }.count
        }

        return DeliverySummaryDTO(
            pending: count(.pending, in: all),
            sent: count(.sent, in: all),
            delivered: count(.delivered, in: all),
            failed: count(.failed, in: all),
            bounced: count(.bounced, in: all),
            last24Hours: DeliveryWindowStatsDTO(
                total: recent.count,
                delivered: count(.delivered, in: recent),
                failed: count(.failed, in: recent) + count(.bounced, in: recent)
            )
        )
    }

    // MARK: - Private delivery

    private static func deliverPush(_ outbox: NotificationOutbox, on database: any Database, app: Application) async {
        let metadata = decodeMetadata(outbox.metadataJSON)
        let result: APNsSendResult

        if let conversationID = metadata.conversationID {
            result = await APNsService.sendAlertWithResult(
                to: outbox.recipient,
                title: outbox.title,
                body: outbox.body,
                conversationID: conversationID,
                on: app
            )
        } else if let sessionID = metadata.sessionID {
            result = await APNsService.sendSessionReminderWithResult(
                to: outbox.recipient,
                title: outbox.title,
                body: outbox.body,
                sessionID: sessionID,
                on: app
            )
        } else {
            result = await APNsService.sendGenericWithResult(
                to: outbox.recipient,
                title: outbox.title,
                body: outbox.body,
                on: app
            )
        }

        if result.accepted {
            outbox.status = NotificationDeliveryStatus.sent.rawValue
            outbox.sentAt = Date()
            outbox.lastError = nil
            outbox.nextRetryAt = nil
        } else {
            if result.invalidDeviceToken, let userID = outbox.$user.id {
                await PushTokenService.invalidate(token: outbox.recipient, userID: userID, reason: result.reason, on: database)
            }
            await markFailed(outbox, error: result.reason ?? "APNs HTTP \(result.statusCode)", retry: !result.invalidDeviceToken, on: database)
        }
    }

    private static func deliverSMS(_ outbox: NotificationOutbox, on database: any Database, app: Application) async {
        let callbackURL = twilioStatusCallbackURL(outboxID: outbox.id)
        let result = await TwilioService.sendSMSWithResult(
            to: outbox.recipient,
            body: outbox.body,
            statusCallbackURL: callbackURL,
            on: app
        )

        if result.success {
            outbox.status = NotificationDeliveryStatus.sent.rawValue
            outbox.sentAt = Date()
            outbox.externalID = result.messageSID
            outbox.lastError = nil
            outbox.nextRetryAt = nil
        } else {
            await markFailed(outbox, error: result.error ?? "Twilio HTTP \(result.statusCode)", retry: true, on: database)
        }
    }

    private static func markFailed(
        _ outbox: NotificationOutbox,
        error: String,
        retry: Bool,
        on database: any Database
    ) async {
        outbox.status = NotificationDeliveryStatus.failed.rawValue
        outbox.failedAt = Date()
        outbox.lastError = error
        if retry {
            scheduleRetryIfNeeded(outbox)
        } else {
            outbox.nextRetryAt = nil
        }
    }

    private static func scheduleRetryIfNeeded(_ outbox: NotificationOutbox) {
        guard outbox.attemptCount < outbox.maxAttempts else {
            outbox.nextRetryAt = nil
            if outbox.channel == NotificationChannel.sms.rawValue {
                outbox.status = NotificationDeliveryStatus.bounced.rawValue
            }
            return
        }
        let index = min(outbox.attemptCount - 1, retryDelays.count - 1)
        outbox.nextRetryAt = Date().addingTimeInterval(retryDelays[max(0, index)])
    }

    private static func twilioStatusCallbackURL(outboxID: UUID?) -> String? {
        guard let base = Environment.get("APP_URL"), !base.isEmpty,
              let outboxID else { return nil }
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return "\(trimmed)/api/webhooks/twilio/sms-status?outboxID=\(outboxID.uuidString)"
    }

    private struct DeliveryMetadata: Codable {
        var conversationID: UUID?
        var sessionID: UUID?
    }

    private static func encodeMetadata(conversationID: UUID?, sessionID: UUID?) -> String? {
        let payload = DeliveryMetadata(conversationID: conversationID, sessionID: sessionID)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeMetadata(_ json: String?) -> DeliveryMetadata {
        guard let json, let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(DeliveryMetadata.self, from: data) else {
            return DeliveryMetadata()
        }
        return payload
    }
}

enum PushTokenService {
    static func activeTokens(for userID: UUID, on database: any Database) async throws -> [PushDeviceToken] {
        try await PushDeviceToken.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$invalidatedAt == nil)
            .all()
    }

    static func invalidate(token: String, userID: UUID, reason: String?, on database: any Database) async {
        guard let record = try? await PushDeviceToken.query(on: database)
            .filter(\.$token == token)
            .filter(\.$user.$id == userID)
            .first() else { return }
        record.invalidatedAt = Date()
        record.lastError = reason
        try? await record.save(on: database)
    }

    static func purgeStaleInvalidTokens(olderThan days: Int = 30, on database: any Database) async {
        let cutoff = Date().addingTimeInterval(-Double(days * 24 * 3600))
        let stale = (try? await PushDeviceToken.query(on: database)
            .filter(\.$invalidatedAt != nil)
            .filter(\.$invalidatedAt <= cutoff)
            .all()) ?? []
        for token in stale {
            try? await token.delete(on: database)
        }
    }
}
