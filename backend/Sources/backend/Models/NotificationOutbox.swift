import Fluent
import Vapor

enum NotificationChannel: String {
    case push
    case sms
}

enum NotificationDeliveryKind: String {
    case sessionReminder = "session_reminder"
    case chatMessage = "chat_message"
    case clientInvite = "client_invite"
    case sessionScheduled = "session_scheduled"
}

enum NotificationDeliveryStatus: String {
    case pending
    case sent
    case delivered
    case failed
    case bounced
}

final class NotificationOutbox: Model, @unchecked Sendable {
    static let schema = "notification_outbox"

    @ID(key: .id) var id: UUID?
    @OptionalParent(key: "user_id") var user: User?
    @Field(key: "channel") var channel: String
    @Field(key: "kind") var kind: String
    @Field(key: "recipient") var recipient: String
    @Field(key: "title") var title: String
    @Field(key: "body") var body: String
    @Field(key: "status") var status: String
    @OptionalField(key: "external_id") var externalID: String?
    @Field(key: "attempt_count") var attemptCount: Int
    @Field(key: "max_attempts") var maxAttempts: Int
    @OptionalField(key: "next_retry_at") var nextRetryAt: Date?
    @OptionalField(key: "last_error") var lastError: String?
    @OptionalField(key: "metadata_json") var metadataJSON: String?
    @OptionalField(key: "scheduled_reminder_id") var scheduledReminderID: UUID?
    @OptionalField(key: "sent_at") var sentAt: Date?
    @OptionalField(key: "delivered_at") var deliveredAt: Date?
    @OptionalField(key: "failed_at") var failedAt: Date?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(
        userID: UUID?,
        channel: String,
        kind: String,
        recipient: String,
        title: String,
        body: String,
        metadataJSON: String? = nil,
        scheduledReminderID: UUID? = nil,
        maxAttempts: Int = 3
    ) {
        if let userID {
            self.$user.id = userID
        }
        self.channel = channel
        self.kind = kind
        self.recipient = recipient
        self.title = title
        self.body = body
        self.status = NotificationDeliveryStatus.pending.rawValue
        self.attemptCount = 0
        self.maxAttempts = maxAttempts
        self.metadataJSON = metadataJSON
        self.scheduledReminderID = scheduledReminderID
    }
}

struct NotificationOutboxDTO: Content {
    let id: UUID
    let userID: UUID?
    let channel: String
    let kind: String
    let recipient: String
    let title: String
    let body: String
    let status: String
    let externalID: String?
    let attemptCount: Int
    let maxAttempts: Int
    let nextRetryAt: Date?
    let lastError: String?
    let sentAt: Date?
    let deliveredAt: Date?
    let failedAt: Date?
    let createdAt: Date?

    init(from row: NotificationOutbox) throws {
        guard let id = row.id else { throw Abort(.internalServerError) }
        self.id = id
        self.userID = row.$user.id
        self.channel = row.channel
        self.kind = row.kind
        self.recipient = Self.maskRecipient(row.recipient, channel: row.channel)
        self.title = row.title
        self.body = row.body
        self.status = row.status
        self.externalID = row.externalID
        self.attemptCount = row.attemptCount
        self.maxAttempts = row.maxAttempts
        self.nextRetryAt = row.nextRetryAt
        self.lastError = row.lastError
        self.sentAt = row.sentAt
        self.deliveredAt = row.deliveredAt
        self.failedAt = row.failedAt
        self.createdAt = row.createdAt
    }

    private static func maskRecipient(_ value: String, channel: String) -> String {
        guard value.count > 8 else { return "••••" }
        if channel == NotificationChannel.sms.rawValue {
            return "••••\(value.suffix(4))"
        }
        return "\(value.prefix(8))…"
    }
}

struct DeliverySummaryDTO: Content {
    let pending: Int
    let sent: Int
    let delivered: Int
    let failed: Int
    let bounced: Int
    let last24Hours: DeliveryWindowStatsDTO
}

struct DeliveryWindowStatsDTO: Content {
    let total: Int
    let delivered: Int
    let failed: Int
}
