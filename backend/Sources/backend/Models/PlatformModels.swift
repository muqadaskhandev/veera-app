import Fluent
import Vapor

// MARK: - Financial

final class FinancialEvent: Model, @unchecked Sendable {
    static let schema = "financial_events"

    @ID(key: .id) var id: UUID?
    @Parent(key: "trainer_id") var trainer: Trainer
    @OptionalParent(key: "client_id") var client: Client?
    @OptionalParent(key: "session_id") var session: Session?
    @Field(key: "kind") var kind: String
    @Field(key: "title") var title: String
    @Field(key: "detail") var detail: String
    @OptionalField(key: "amount") var amount: Double?
    @Field(key: "session_delta") var sessionDelta: Int
    @Field(key: "occurred_at") var occurredAt: Date
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(
        trainerID: UUID,
        clientID: UUID?,
        sessionID: UUID?,
        kind: String,
        title: String,
        detail: String,
        amount: Double?,
        sessionDelta: Int,
        occurredAt: Date
    ) {
        self.$trainer.id = trainerID
        if let clientID { self.$client.id = clientID }
        if let sessionID { self.$session.id = sessionID }
        self.kind = kind
        self.title = title
        self.detail = detail
        self.amount = amount
        self.sessionDelta = sessionDelta
        self.occurredAt = occurredAt
    }
}

struct FinancialEventDTO: Content {
    let id: UUID
    let trainerID: UUID
    let clientID: UUID?
    let sessionID: UUID?
    let clientName: String?
    let kind: String
    let title: String
    let detail: String
    let amount: Double?
    let sessionDelta: Int
    let occurredAt: Date

    init(from event: FinancialEvent, clientName: String?) throws {
        guard let id = event.id else { throw Abort(.internalServerError) }
        self.id = id
        self.trainerID = event.$trainer.id
        self.clientID = event.$client.id
        self.sessionID = event.$session.id
        self.clientName = clientName
        self.kind = event.kind
        self.title = event.title
        self.detail = event.detail
        self.amount = event.amount
        self.sessionDelta = event.sessionDelta
        self.occurredAt = event.occurredAt
    }
}

struct FinancialSummaryDTO: Content {
    let revenue: Double
    let sessionsUsed: Int
    let events: [FinancialEventDTO]
    let buckets: [FinancialBucketDTO]
}

struct FinancialBucketDTO: Content {
    let label: String
    let revenue: Double
    let sessions: Int
}

struct CreateFinancialEventRequest: Content {
    var clientID: UUID
    var kind: String
    var title: String
    var detail: String?
    var amount: Double?
    var sessionDelta: Int?
    var occurredAt: Date?
}

// MARK: - Weight

final class WeightLog: Model, @unchecked Sendable {
    static let schema = "weight_logs"

    @ID(key: .id) var id: UUID?
    @Parent(key: "client_id") var client: Client
    @OptionalParent(key: "logged_by_user_id") var loggedBy: User?
    @Field(key: "kg") var kg: Double
    @Field(key: "recorded_at") var recordedAt: Date
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(clientID: UUID, loggedByUserID: UUID?, kg: Double, recordedAt: Date) {
        self.$client.id = clientID
        if let loggedByUserID { self.$loggedBy.id = loggedByUserID }
        self.kg = kg
        self.recordedAt = recordedAt
    }
}

struct WeightLogDTO: Content {
    let id: UUID
    let kg: Double
    let recordedAt: Date

    init(from log: WeightLog) throws {
        guard let id = log.id else { throw Abort(.internalServerError) }
        self.id = id
        self.kg = log.kg
        self.recordedAt = log.recordedAt
    }
}

struct LogWeightRequest: Content {
    var kg: Double
    var recordedAt: Date?
}

// MARK: - Progress photos

final class ProgressPhoto: Model, @unchecked Sendable {
    static let schema = "progress_photos"

    @ID(key: .id) var id: UUID?
    @Parent(key: "client_id") var client: Client
    @Field(key: "image_path") var imagePath: String
    @Field(key: "captured_at") var capturedAt: Date
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(clientID: UUID, imagePath: String, capturedAt: Date) {
        self.$client.id = clientID
        self.imagePath = imagePath
        self.capturedAt = capturedAt
    }
}

struct ProgressPhotoDTO: Content {
    let id: UUID
    let imageURL: String
    let capturedAt: Date

    init(from photo: ProgressPhoto, baseURL: String?) throws {
        guard let id = photo.id else { throw Abort(.internalServerError) }
        self.id = id
        self.imageURL = StorageService.publicURL(for: photo.imagePath, baseURL: baseURL) ?? photo.imagePath
        self.capturedAt = photo.capturedAt
    }
}

// MARK: - Nutrition

final class NutritionProfile: Model, @unchecked Sendable {
    static let schema = "nutrition_profiles"

    @ID(key: .id) var id: UUID?
    @Parent(key: "client_id") var client: Client
    @Field(key: "protein_g") var proteinG: Int
    @Field(key: "carbs_g") var carbsG: Int
    @Field(key: "fats_g") var fatsG: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(clientID: UUID, proteinG: Int, carbsG: Int, fatsG: Int) {
        self.$client.id = clientID
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatsG = fatsG
    }
}

final class NutritionNote: Model, @unchecked Sendable {
    static let schema = "nutrition_notes"

    @ID(key: .id) var id: UUID?
    @Parent(key: "client_id") var client: Client
    @Field(key: "text") var text: String
    @Field(key: "sort_order") var sortOrder: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(clientID: UUID, text: String, sortOrder: Int) {
        self.$client.id = clientID
        self.text = text
        self.sortOrder = sortOrder
    }
}

final class Supplement: Model, @unchecked Sendable {
    static let schema = "supplements"

    @ID(key: .id) var id: UUID?
    @Parent(key: "client_id") var client: Client
    @Field(key: "name") var name: String
    @Field(key: "dosage") var dosage: String
    @Field(key: "sort_order") var sortOrder: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(clientID: UUID, name: String, dosage: String, sortOrder: Int) {
        self.$client.id = clientID
        self.name = name
        self.dosage = dosage
        self.sortOrder = sortOrder
    }
}

struct NutritionProfileDTO: Content {
    let proteinG: Int
    let carbsG: Int
    let fatsG: Int
    let calories: Int
    let notes: [NutritionNoteDTO]
    let supplements: [SupplementDTO]
}

struct NutritionNoteDTO: Content {
    let id: UUID
    let text: String

    init(from note: NutritionNote) throws {
        guard let id = note.id else { throw Abort(.internalServerError) }
        self.id = id
        self.text = note.text
    }
}

struct SupplementDTO: Content {
    let id: UUID
    let name: String
    let dosage: String

    init(from supplement: Supplement) throws {
        guard let id = supplement.id else { throw Abort(.internalServerError) }
        self.id = id
        self.name = supplement.name
        self.dosage = supplement.dosage
    }
}

struct UpdateNutritionRequest: Content {
    var proteinG: Int?
    var carbsG: Int?
    var fatsG: Int?
    var notes: [NutritionNoteInput]?
    var supplements: [SupplementInput]?
}

struct NutritionNoteInput: Content {
    var id: UUID?
    var text: String
}

struct SupplementInput: Content {
    var id: UUID?
    var name: String
    var dosage: String
}

// MARK: - Workouts

final class WorkoutWeek: Model, @unchecked Sendable {
    static let schema = "workout_weeks"

    @ID(key: .id) var id: UUID?
    @Parent(key: "client_id") var client: Client
    @Field(key: "week_index") var weekIndex: Int
    @Field(key: "days_json") var daysJSON: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(clientID: UUID, weekIndex: Int, daysJSON: String) {
        self.$client.id = clientID
        self.weekIndex = weekIndex
        self.daysJSON = daysJSON
    }
}

struct WorkoutDayPayload: Content {
    var id: UUID?
    var label: String
    var focus: String?
    var exercises: [WorkoutExercisePayload]
}

struct WorkoutExercisePayload: Content {
    var id: UUID?
    var exerciseID: UUID?
    var name: String
    var category: String?
    var sets: Int?
    var reps: Int?
    var kind: String
}

struct WorkoutWeekResponse: Content {
    let weekIndex: Int
    let weekCount: Int
    let days: [WorkoutDayPayload]
}

struct SaveWorkoutWeekRequest: Content {
    var days: [WorkoutDayPayload]
    var weekCount: Int?
}

// MARK: - Exercise library

final class Exercise: Model, @unchecked Sendable {
    static let schema = "exercises"

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Field(key: "category") var category: String
    @Field(key: "description") var description: String?
    @Field(key: "image_path") var imagePath: String?
    @Field(key: "video_path") var videoPath: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(name: String, category: String, description: String? = nil, imagePath: String? = nil, videoPath: String? = nil) {
        self.name = name
        self.category = category
        self.description = description
        self.imagePath = imagePath
        self.videoPath = videoPath
    }

    static let seedNames: [String] = [
        "Back Squat", "Front Squat", "Bench Press", "Incline Bench Press", "Deadlift",
        "Romanian Deadlift", "Overhead Press", "Pull-Ups", "Chin-Ups", "Barbell Row",
        "Lat Pulldown", "Walking Lunge", "Bulgarian Split Squat", "Leg Press", "Hip Thrust",
        "Face Pull", "Lateral Raise", "Bicep Curl", "Tricep Pushdown", "Plank",
        "Hanging Leg Raise", "Kettlebell Swing", "Assault Bike", "Box Jump",
    ]
}

struct ExerciseDTO: Content {
    let id: UUID
    let name: String
    let category: String
    let description: String?
    let imageURL: String?
    let videoURL: String?

    init(from exercise: Exercise, baseURL: String?) throws {
        guard let id = exercise.id else { throw Abort(.internalServerError) }
        self.id = id
        self.name = exercise.name
        self.category = exercise.category
        self.description = exercise.description
        self.imageURL = exercise.imagePath.flatMap { StorageService.publicURL(for: $0, baseURL: baseURL) }
        self.videoURL = exercise.videoPath.flatMap { StorageService.publicURL(for: $0, baseURL: baseURL) }
    }
}

// MARK: - Notifications

final class UserNotification: Model, @unchecked Sendable {
    static let schema = "user_notifications"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "category") var category: String
    @Field(key: "title") var title: String
    @Field(key: "body") var body: String
    @OptionalField(key: "metadata_json") var metadataJSON: String?
    @OptionalField(key: "read_at") var readAt: Date?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(userID: UUID, category: String, title: String, body: String, metadataJSON: String? = nil) {
        self.$user.id = userID
        self.category = category
        self.title = title
        self.body = body
        self.metadataJSON = metadataJSON
    }
}

struct UserNotificationDTO: Content {
    let id: UUID
    let category: String
    let title: String
    let body: String
    let isRead: Bool
    let createdAt: Date?

    init(from notification: UserNotification) throws {
        guard let id = notification.id else { throw Abort(.internalServerError) }
        self.id = id
        self.category = notification.category
        self.title = notification.title
        self.body = notification.body
        self.isRead = notification.readAt != nil
        self.createdAt = notification.createdAt
    }
}

final class NotificationPreferences: Model, @unchecked Sendable {
    static let schema = "notification_preferences"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "notify_schedule") var notifySchedule: Bool
    @Field(key: "notify_messages") var notifyMessages: Bool
    @Field(key: "notify_activity") var notifyActivity: Bool
    @Field(key: "sms_enabled") var smsEnabled: Bool
    @Field(key: "reminder_minutes_before") var reminderMinutesBefore: Int
    @Field(key: "notifications_enabled") var notificationsEnabled: Bool
    @Field(key: "notify_money") var notifyMoney: Bool
    @Field(key: "activity_mode") var activityMode: String
    @Field(key: "quiet_hours_enabled") var quietHoursEnabled: Bool
    @Field(key: "quiet_start_minutes") var quietStartMinutes: Int
    @Field(key: "quiet_end_minutes") var quietEndMinutes: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(userID: UUID) {
        self.$user.id = userID
        self.notifySchedule = true
        self.notifyMessages = true
        self.notifyActivity = true
        self.smsEnabled = false
        self.reminderMinutesBefore = 60
        self.notificationsEnabled = true
        self.notifyMoney = true
        self.activityMode = "personalBests"
        self.quietHoursEnabled = true
        self.quietStartMinutes = 22 * 60
        self.quietEndMinutes = 6 * 60
    }
}

struct NotificationPreferencesDTO: Content {
    let notificationsEnabled: Bool
    let notifyMoney: Bool
    let notifySchedule: Bool
    let notifyMessages: Bool
    let notifyActivity: Bool
    let activityMode: String
    let quietHoursEnabled: Bool
    let quietStartMinutes: Int
    let quietEndMinutes: Int
    let smsEnabled: Bool
    let reminderMinutesBefore: Int

    init(from prefs: NotificationPreferences) {
        self.notificationsEnabled = prefs.notificationsEnabled
        self.notifyMoney = prefs.notifyMoney
        self.notifySchedule = prefs.notifySchedule
        self.notifyMessages = prefs.notifyMessages
        self.notifyActivity = prefs.notifyActivity
        self.activityMode = prefs.activityMode
        self.quietHoursEnabled = prefs.quietHoursEnabled
        self.quietStartMinutes = prefs.quietStartMinutes
        self.quietEndMinutes = prefs.quietEndMinutes
        self.smsEnabled = prefs.smsEnabled
        self.reminderMinutesBefore = prefs.reminderMinutesBefore
    }
}

struct UpdateNotificationPreferencesRequest: Content {
    var notificationsEnabled: Bool?
    var notifyMoney: Bool?
    var notifySchedule: Bool?
    var notifyMessages: Bool?
    var notifyActivity: Bool?
    var activityMode: String?
    var quietHoursEnabled: Bool?
    var quietStartMinutes: Int?
    var quietEndMinutes: Int?
    var smsEnabled: Bool?
    var reminderMinutesBefore: Int?
}

// MARK: - Reminders

final class ScheduledReminder: Model, @unchecked Sendable {
    static let schema = "scheduled_reminders"

    @ID(key: .id) var id: UUID?
    @Parent(key: "session_id") var session: Session
    @Parent(key: "user_id") var user: User
    @Field(key: "channel") var channel: String
    @Field(key: "fire_at") var fireAt: Date
    @OptionalField(key: "sent_at") var sentAt: Date?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(sessionID: UUID, userID: UUID, channel: String, fireAt: Date) {
        self.$session.id = sessionID
        self.$user.id = userID
        self.channel = channel
        self.fireAt = fireAt
    }
}

// MARK: - Support

final class SupportTicket: Model, @unchecked Sendable {
    static let schema = "support_tickets"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "topic") var topic: String
    @Field(key: "message") var message: String
    @OptionalField(key: "attachment_path") var attachmentPath: String?
    @Field(key: "status") var status: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(userID: UUID, topic: String, message: String, attachmentPath: String?) {
        self.$user.id = userID
        self.topic = topic
        self.message = message
        self.attachmentPath = attachmentPath
        self.status = "open"
    }
}

struct SupportTicketDTO: Content {
    let id: UUID
    let topic: String
    let status: String
    let createdAt: Date?

    init(from ticket: SupportTicket) throws {
        guard let id = ticket.id else { throw Abort(.internalServerError) }
        self.id = id
        self.topic = ticket.topic
        self.status = ticket.status
        self.createdAt = ticket.createdAt
    }
}

// MARK: - Subscriptions

final class Subscription: Model, @unchecked Sendable {
    static let schema = "subscriptions"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "product_id") var productID: String
    @Field(key: "original_transaction_id") var originalTransactionID: String
    @OptionalField(key: "latest_receipt") var latestReceipt: String?
    @Field(key: "status") var status: String
    @OptionalField(key: "started_at") var startedAt: Date?
    @OptionalField(key: "expires_at") var expiresAt: Date?
    @OptionalField(key: "expiry_notified_at") var expiryNotifiedAt: Date?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(userID: UUID, productID: String, originalTransactionID: String, latestReceipt: String?, status: String, startedAt: Date? = nil, expiresAt: Date?) {
        self.$user.id = userID
        self.productID = productID
        self.originalTransactionID = originalTransactionID
        self.latestReceipt = latestReceipt
        self.status = status
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }
}

struct SubscriptionDTO: Content {
    let productID: String
    let status: String
    let startedAt: Date?
    let expiresAt: Date?
    let isActive: Bool

    init(from subscription: Subscription) {
        self.productID = subscription.productID
        self.status = subscription.status
        self.startedAt = subscription.startedAt
        self.expiresAt = subscription.expiresAt
        self.isActive = subscription.status == "active" && (subscription.expiresAt.map { $0 > Date() } ?? true)
    }
}

struct ValidateReceiptRequest: Content {
    var receiptData: String
    var productID: String
}
