import Fluent
import Foundation
import Vapor

enum SessionService {
    static func list(for user: User, from: Date?, to: Date?, on database: any Database) async throws -> [SessionDTO] {
        var query = Session.query(on: database).sort(\.$scheduledAt, .ascending)

        switch user.userRole {
        case .trainer:
            let trainer = try await ClientAccessService.trainer(for: user, on: database)
            query = query.filter(\.$trainer.$id == trainer.id!)
        case .client:
            guard let client = try await Client.query(on: database).filter(\.$user.$id == user.id!).first() else {
                return []
            }
            query = query.filter(\.$client.$id == client.id!)
        case .admin:
            break
        case .none:
            throw Abort(.forbidden)
        }

        if let from { query = query.filter(\.$scheduledAt >= from) }
        if let to { query = query.filter(\.$scheduledAt <= to) }

        return try await query.all().map { try SessionDTO(from: $0) }
    }

    static func create(
        for user: User,
        payload: CreateSessionRequest,
        on database: any Database,
        app: Application
    ) async throws -> SessionDTO {
        let trainer: Trainer
        if user.userRole == .admin {
            if let trainerID = payload.trainerID, let resolved = try await Trainer.find(trainerID, on: database) {
                trainer = resolved
            } else if let clientID = payload.clientID {
                trainer = try await ClientAccessService.trainerForClient(clientID, on: database)
            } else {
                trainer = try await ClientAccessService.trainer(for: user, on: database)
            }
        } else {
            trainer = try await ClientAccessService.trainer(for: user, on: database)
        }

        let session = Session(
            trainerID: try trainer.requireID(),
            clientID: payload.clientID,
            clientName: payload.clientName,
            focus: payload.focus,
            location: payload.location ?? "",
            accent: payload.accent,
            initials: payload.initials,
            scheduledAt: payload.scheduledAt,
            durationMinutes: payload.durationMinutes ?? 60,
            notes: payload.notes ?? ""
        )
        try await session.save(on: database)

        try await SessionReminderScheduler.reschedule(for: session, on: database, app: app)
        try await notifySessionCreated(session, trainer: trainer, on: database, app: app)

        return try SessionDTO(from: session)
    }

    static func update(
        sessionID: UUID,
        for user: User,
        payload: UpdateSessionRequest,
        on database: any Database,
        app: Application
    ) async throws -> SessionDTO {
        let session = try await requireSession(sessionID, for: user, on: database)

        if let clientID = payload.clientID { session.$client.id = clientID }
        if let clientName = payload.clientName { session.clientName = clientName }
        if let focus = payload.focus { session.focus = focus }
        if let location = payload.location { session.location = location }
        if let accent = payload.accent { session.accent = accent }
        if let initials = payload.initials { session.initials = initials }
        if let scheduledAt = payload.scheduledAt { session.scheduledAt = scheduledAt }
        if let durationMinutes = payload.durationMinutes { session.durationMinutes = durationMinutes }
        if let notes = payload.notes { session.notes = notes }
        if let isCompleted = payload.isCompleted { session.isCompleted = isCompleted }
        if let isSkipped = payload.isSkipped { session.isSkipped = isSkipped }

        try await session.save(on: database)

        if payload.isCompleted == true {
            try await handleSessionCompleted(session, on: database)
        }

        if payload.isSkipped == true || payload.isCancelled == true {
            try await SessionReminderScheduler.cancel(for: session, on: database)
        } else {
            try await SessionReminderScheduler.reschedule(for: session, on: database, app: app)
        }

        if payload.isCancelled == true {
            try await notifySessionCancelled(session, on: database, app: app)
        }

        return try SessionDTO(from: session)
    }

    static func delete(sessionID: UUID, for user: User, on database: any Database, app: Application) async throws {
        let session = try await requireSession(sessionID, for: user, on: database)
        try await SessionReminderScheduler.cancel(for: session, on: database)
        try await session.delete(on: database)
    }

    private static func requireSession(_ id: UUID, for user: User, on database: any Database) async throws -> Session {
        guard let session = try await Session.find(id, on: database) else {
            throw Abort(.notFound, reason: "Session not found")
        }

        switch user.userRole {
        case .admin:
            return session
        case .trainer:
            let trainer = try await ClientAccessService.trainer(for: user, on: database)
            guard session.$trainer.id == trainer.id else {
                throw Abort(.forbidden, reason: "Not your session")
            }
            return session
        case .client:
            guard let client = try await Client.query(on: database).filter(\.$user.$id == user.id!).first(),
                  session.$client.id == client.id || session.clientName == client.name else {
                throw Abort(.forbidden, reason: "Not your session")
            }
            return session
        case .none:
            throw Abort(.forbidden)
        }
    }

    private static func handleSessionCompleted(_ session: Session, on database: any Database) async throws {
        guard let clientID = session.$client.id,
              let client = try await Client.find(clientID, on: database) else { return }

        if client.sessionsRemaining > 0 {
            client.sessionsRemaining -= 1
            try await client.save(on: database)
        }

        let event = FinancialEvent(
            trainerID: session.$trainer.id,
            clientID: clientID,
            sessionID: session.id,
            kind: "usage",
            title: "Session completed",
            detail: session.focus,
            amount: nil,
            sessionDelta: -1,
            occurredAt: session.scheduledAt
        )
        try await event.save(on: database)
    }

    private static func notifySessionCreated(_ session: Session, trainer: Trainer, on database: any Database, app: Application) async throws {
        guard let clientID = session.$client.id,
              let client = try await Client.find(clientID, on: database),
              let userID = client.$user.id,
              let clientUser = try await User.find(userID, on: database) else { return }

        try await NotificationService.create(
            userID: userID,
            category: "schedule",
            title: "New session scheduled",
            body: "\(trainer.name) scheduled \(session.focus) on \(Self.timeLabel(session.scheduledAt)).",
            on: database
        )

        let prefs = try await NotificationService.preferences(for: clientUser, on: database)
        if prefs.smsEnabled, !client.phone.isEmpty {
            let body = TwilioService.sessionReminderMessage(
                clientName: client.name,
                focus: session.focus,
                timeLabel: Self.timeLabel(session.scheduledAt),
                location: session.location
            )
            _ = try? await NotificationDeliveryService.sendSMS(
                userID: userID,
                phone: client.phone,
                title: "New session scheduled",
                body: "New session: \(body)",
                kind: .sessionScheduled,
                on: database,
                app: app
            )
        }
    }

    private static func notifySessionCancelled(_ session: Session, on database: any Database, app: Application) async throws {
        guard let clientID = session.$client.id,
              let client = try await Client.find(clientID, on: database),
              let userID = client.$user.id else { return }

        try await NotificationService.create(
            userID: userID,
            category: "schedule",
            title: "Session cancelled",
            body: "Your \(session.focus) session on \(Self.timeLabel(session.scheduledAt)) was cancelled.",
            on: database
        )
    }

    static func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct UpdateSessionRequest: Content {
    var clientID: UUID?
    var clientName: String?
    var focus: String?
    var location: String?
    var accent: String?
    var initials: String?
    var scheduledAt: Date?
    var durationMinutes: Int?
    var notes: String?
    var isCompleted: Bool?
    var isSkipped: Bool?
    var isCancelled: Bool?
}
