import Fluent
import Vapor

final class Session: Model, @unchecked Sendable {
    static let schema = "sessions"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "trainer_id")
    var trainer: Trainer

    @OptionalParent(key: "client_id")
    var client: Client?

    @Field(key: "client_name")
    var clientName: String

    @Field(key: "focus")
    var focus: String

    @Field(key: "location")
    var location: String

    @Field(key: "accent")
    var accent: String

    @Field(key: "initials")
    var initials: String

    @Field(key: "scheduled_at")
    var scheduledAt: Date

    @Field(key: "duration_minutes")
    var durationMinutes: Int

    @Field(key: "notes")
    var notes: String

    @Field(key: "is_completed")
    var isCompleted: Bool

    @Field(key: "is_skipped")
    var isSkipped: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        trainerID: UUID,
        clientID: UUID? = nil,
        clientName: String,
        focus: String,
        location: String = "",
        accent: String,
        initials: String,
        scheduledAt: Date,
        durationMinutes: Int = 60,
        notes: String = "",
        isCompleted: Bool = false,
        isSkipped: Bool = false
    ) {
        self.id = id
        self.$trainer.id = trainerID
        if let clientID {
            self.$client.id = clientID
        }
        self.clientName = clientName
        self.focus = focus
        self.location = location
        self.accent = accent
        self.initials = initials
        self.scheduledAt = scheduledAt
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.isCompleted = isCompleted
        self.isSkipped = isSkipped
    }
}

extension Session: Content {}

struct SessionDTO: Content {
    let id: UUID
    let trainerID: UUID
    let clientID: UUID?
    let clientName: String
    let focus: String
    let location: String
    let accent: String
    let initials: String
    let scheduledAt: Date
    let durationMinutes: Int
    let notes: String
    let isCompleted: Bool
    let isSkipped: Bool

    init(from session: Session) throws {
        guard let id = session.id else {
            throw Abort(.internalServerError, reason: "Session missing id")
        }
        self.id = id
        self.trainerID = session.$trainer.id
        self.clientID = session.$client.id
        self.clientName = session.clientName
        self.focus = session.focus
        self.location = session.location
        self.accent = session.accent
        self.initials = session.initials
        self.scheduledAt = session.scheduledAt
        self.durationMinutes = session.durationMinutes
        self.notes = session.notes
        self.isCompleted = session.isCompleted
        self.isSkipped = session.isSkipped
    }
}

struct CreateSessionRequest: Content {
    var clientID: UUID?
    var clientName: String
    var focus: String
    var location: String?
    var accent: String
    var initials: String
    var scheduledAt: Date
    var durationMinutes: Int?
    var notes: String?
}
