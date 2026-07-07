import Crypto
import Fluent
import Foundation
import Vapor

struct AdminUserDTO: Content {
    let id: UUID
    let email: String?
    let role: String
    let displayName: String
    let isEmailVerified: Bool
    let isActive: Bool
    let lastSeenAt: Date?
    let createdAt: Date?

    init(from user: User) throws {
        guard let id = user.id else { throw Abort(.internalServerError) }
        self.id = id
        self.email = user.email
        self.role = user.role
        self.displayName = user.displayName
        self.isEmailVerified = user.isEmailVerified
        self.isActive = user.isActive
        self.lastSeenAt = user.lastSeenAt
        self.createdAt = user.createdAt
    }
}

struct AdminRoleCountsDTO: Content {
    let total: Int
    let trainers: Int
    let clients: Int
    let admins: Int
    let active: Int
    let inactive: Int
}

struct AdminDashboardDTO: Content {
    let users: AdminRoleCountsDTO
    let subscriptions: AdminSubscriptionStatsDTO
    let sessions: AdminSessionStatsDTO
    let deliveries: DeliverySummaryDTO
    let invites: AdminInviteStatsDTO
    let recentUsers: [AdminUserDTO]
}

struct AdminSubscriptionStatsDTO: Content {
    let total: Int
    let active: Int
    let expired: Int
}

struct AdminSessionStatsDTO: Content {
    let total: Int
    let upcoming: Int
    let completedThisWeek: Int
}

struct AdminInviteStatsDTO: Content {
    let total: Int
    let redeemable: Int
    let redeemed: Int
}

struct AdminSubscriptionRowDTO: Content {
    let id: UUID
    let userID: UUID
    let userEmail: String?
    let userName: String
    let productID: String
    let status: String
    let startedAt: Date?
    let expiresAt: Date?
    let isActive: Bool
    let createdAt: Date?
}

struct AdminSessionRowDTO: Content {
    let id: UUID
    let clientName: String
    let focus: String
    let scheduledAt: Date
    let isCompleted: Bool
    let isSkipped: Bool
}

struct AdminInviteRowDTO: Content {
    let id: UUID
    let code: String
    let trainerID: UUID
    let invitedEmail: String?
    let expiresAt: Date?
    let redeemedAt: Date?
    let isRedeemable: Bool
    let createdAt: Date?
}

enum AdminService {
    static func dashboard(on database: any Database) async throws -> AdminDashboardDTO {
        let users = try await User.query(on: database).all()
        let roleCounts = AdminRoleCountsDTO(
            total: users.count,
            trainers: users.filter { $0.role == UserRole.trainer.rawValue }.count,
            clients: users.filter { $0.role == UserRole.client.rawValue }.count,
            admins: users.filter { $0.role == UserRole.admin.rawValue }.count,
            active: users.filter(\.isActive).count,
            inactive: users.filter { !$0.isActive }.count
        )

        let subscriptions = try await Subscription.query(on: database).all()
        let now = Date()
        let subStats = AdminSubscriptionStatsDTO(
            total: subscriptions.count,
            active: subscriptions.filter {
                $0.status == "active" && ($0.expiresAt.map { $0 > now } ?? true)
            }.count,
            expired: subscriptions.filter {
                $0.status != "active" || ($0.expiresAt.map { $0 <= now } ?? false)
            }.count
        )

        let sessions = try await Session.query(on: database).all()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let sessionStats = AdminSessionStatsDTO(
            total: sessions.count,
            upcoming: sessions.filter { !$0.isCompleted && !$0.isSkipped && $0.scheduledAt > now }.count,
            completedThisWeek: sessions.filter { $0.isCompleted && ($0.scheduledAt >= weekAgo) }.count
        )

        let deliverySummary = try await NotificationDeliveryService.adminSummary(on: database)

        let invites = try await InviteCode.query(on: database).all()
        let inviteStats = AdminInviteStatsDTO(
            total: invites.count,
            redeemable: invites.filter(\.isRedeemable).count,
            redeemed: invites.filter { $0.redeemedAt != nil }.count
        )

        let recentUsers = try users
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .prefix(8)
            .map { try AdminUserDTO(from: $0) }

        return AdminDashboardDTO(
            users: roleCounts,
            subscriptions: subStats,
            sessions: sessionStats,
            deliveries: deliverySummary,
            invites: inviteStats,
            recentUsers: recentUsers
        )
    }

    static func listUsers(role: String?, search: String?, limit: Int, on database: any Database) async throws -> [AdminUserDTO] {
        var query = User.query(on: database).sort(\.$createdAt, .descending)
        if let role, !role.isEmpty {
            query = query.filter(\.$role == role)
        }
        var users = try await query.limit(min(max(limit, 1), 500)).all()
        let trimmed = search?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !trimmed.isEmpty {
            users = users.filter {
                $0.displayName.lowercased().contains(trimmed)
                    || ($0.email?.lowercased().contains(trimmed) ?? false)
            }
        }
        return try users.map { try AdminUserDTO(from: $0) }
    }

    static func userDetail(id: UUID, on database: any Database) async throws -> AdminUserDetailDTO {
        guard let user = try await User.find(id, on: database) else {
            throw Abort(.notFound, reason: "User not found")
        }

        let subscription = try await Subscription.query(on: database)
            .filter(\.$user.$id == id)
            .sort(\.$updatedAt, .descending)
            .first()

        var trainerID: UUID?
        var clientID: UUID?
        if user.role == UserRole.trainer.rawValue {
            trainerID = try await Trainer.query(on: database).filter(\.$user.$id == id).first()?.id
        }
        if user.role == UserRole.client.rawValue {
            clientID = try await Client.query(on: database).filter(\.$user.$id == id).first()?.id
        }

        return AdminUserDetailDTO(
            user: try AdminUserDTO(from: user),
            subscription: subscription.map { AdminSubscriptionRowDTO(from: $0, user: user) },
            trainerID: trainerID,
            clientID: clientID
        )
    }

    static func listSubscriptions(limit: Int, on database: any Database) async throws -> [AdminSubscriptionRowDTO] {
        let rows = try await Subscription.query(on: database)
            .sort(\.$updatedAt, .descending)
            .limit(min(max(limit, 1), 200))
            .with(\.$user)
            .all()
        return rows.map { AdminSubscriptionRowDTO(from: $0, user: $0.user) }
    }

    static func listRecentSessions(limit: Int, on database: any Database) async throws -> [AdminSessionRowDTO] {
        try await Session.query(on: database)
            .sort(\.$scheduledAt, .descending)
            .limit(min(max(limit, 1), 100))
            .all()
            .compactMap { session in
                guard let id = session.id else { return nil }
                return AdminSessionRowDTO(
                    id: id,
                    clientName: session.clientName,
                    focus: session.focus,
                    scheduledAt: session.scheduledAt,
                    isCompleted: session.isCompleted,
                    isSkipped: session.isSkipped
                )
            }
    }

    static func listInvites(limit: Int, on database: any Database) async throws -> [AdminInviteRowDTO] {
        try await InviteCode.query(on: database)
            .sort(\.$createdAt, .descending)
            .limit(min(max(limit, 1), 200))
            .all()
            .compactMap { invite in
                guard let id = invite.id else { return nil }
                return AdminInviteRowDTO(
                    id: id,
                    code: invite.code,
                    trainerID: invite.$trainer.id,
                    invitedEmail: invite.invitedEmail,
                    expiresAt: invite.expiresAt,
                    redeemedAt: invite.redeemedAt,
                    isRedeemable: invite.isRedeemable,
                    createdAt: invite.createdAt
                )
            }
    }

    static func listExercises(limit: Int, on database: any Database) async throws -> [ExerciseDTO] {
        let exercises = try await Exercise.query(on: database)
            .sort(\.$name, .ascending)
            .limit(min(max(limit, 1), 500))
            .all()
        return try exercises.map { try ExerciseDTO(from: $0, baseURL: Environment.get("APP_URL")) }
    }

    static func deleteExercise(id: UUID, on database: any Database) async throws {
        guard let exercise = try await Exercise.find(id, on: database) else {
            throw Abort(.notFound, reason: "Exercise not found")
        }
        try await exercise.delete(on: database)
    }

    static func createExercise(
        payload: CreateExerciseRequest,
        on database: any Database
    ) async throws -> ExerciseDTO {
        try await ExerciseService.create(
            payload: payload,
            on: database,
            baseURL: Environment.get("APP_URL")
        )
    }

    static func updateExercise(
        id: UUID,
        payload: UpdateExerciseRequest,
        on database: any Database
    ) async throws -> ExerciseDTO {
        try await ExerciseService.update(
            id: id,
            payload: payload,
            on: database,
            baseURL: Environment.get("APP_URL")
        )
    }

    static func listClients(limit: Int, on database: any Database) async throws -> [ClientDTO] {
        let rows = try await Client.query(on: database)
            .sort(\.$name, .ascending)
            .limit(min(max(limit, 1), 500))
            .all()
        var result: [ClientDTO] = []
        for client in rows {
            result.append(try await ClientDTO.make(from: client, on: database))
        }
        return result
    }

    static func listTrainers(limit: Int, on database: any Database) async throws -> [TrainerDTO] {
        try await Trainer.query(on: database)
            .sort(\.$name, .ascending)
            .limit(min(max(limit, 1), 200))
            .all()
            .map { try TrainerDTO(from: $0) }
    }

    static func deleteClient(id: UUID, on database: any Database) async throws {
        guard let client = try await Client.find(id, on: database) else {
            throw Abort(.notFound, reason: "Client not found")
        }
        try await deleteClientRecords(client, on: database)
    }

    static func createUser(
        payload: AdminCreateUserRequest,
        on database: any Database
    ) async throws -> AdminUserDetailDTO {
        try validatePassword(payload.password)
        guard let role = UserRole(rawValue: payload.role) else {
            throw Abort(.badRequest, reason: "Invalid role")
        }

        let normalizedEmail = payload.email.lowercased()
        if try await User.query(on: database).filter(\.$email == normalizedEmail).first() != nil {
            throw Abort(.conflict, reason: "Email already registered")
        }

        let user = User(
            email: normalizedEmail,
            passwordHash: try Bcrypt.hash(payload.password),
            role: role,
            displayName: payload.displayName,
            isEmailVerified: payload.isEmailVerified ?? true
        )
        try await user.save(on: database)
        let userID = try user.requireID()

        switch role {
        case .trainer:
            let trainer = Trainer(name: user.displayName, title: "Strength Coach", bio: "")
            trainer.$user.id = userID
            try await trainer.save(on: database)
            let profile = Profile(
                userID: userID,
                displayName: user.displayName,
                title: "Strength Coach",
                bio: "",
                specialtiesJSON: "[]"
            )
            try await profile.save(on: database)
        case .client:
            let trainerID: UUID
            if let specified = payload.trainerID {
                guard try await Trainer.find(specified, on: database) != nil else {
                    throw Abort(.badRequest, reason: "Trainer not found")
                }
                trainerID = specified
            } else {
                trainerID = try await TrainerService.defaultTrainer(on: database).requireID()
            }
            let initials = Self.initials(from: payload.displayName)
            let client = Client(
                trainerID: trainerID,
                name: payload.displayName,
                initials: initials,
                sessionsRemaining: payload.sessionsRemaining ?? 0,
                daysLeftOnPlan: 30,
                status: "active",
                email: normalizedEmail,
                phone: "",
                age: nil,
                gender: "",
                heightCm: nil,
                weightKg: nil,
                injuryHistory: "",
                primaryGoal: "",
                skillLevel: "",
                note: ""
            )
            client.$user.id = userID
            try await client.save(on: database)
        case .admin:
            break
        }

        return try await userDetail(id: userID, on: database)
    }

    static func updateUser(
        id: UUID,
        payload: AdminUpdateUserRequest,
        on database: any Database
    ) async throws -> AdminUserDetailDTO {
        guard let user = try await User.find(id, on: database) else {
            throw Abort(.notFound, reason: "User not found")
        }

        if let email = payload.email {
            let normalized = email.lowercased()
            if try await User.query(on: database)
                .filter(\.$email == normalized)
                .filter(\.$id != id)
                .first() != nil {
                throw Abort(.conflict, reason: "Email already in use")
            }
            user.email = normalized
        }
        if let displayName = payload.displayName { user.displayName = displayName }
        if let isActive = payload.isActive { user.isActive = isActive }
        if let isEmailVerified = payload.isEmailVerified { user.isEmailVerified = isEmailVerified }
        if let password = payload.password {
            try validatePassword(password)
            user.passwordHash = try Bcrypt.hash(password)
        }
        if let roleRaw = payload.role {
            guard let newRole = UserRole(rawValue: roleRaw) else {
                throw Abort(.badRequest, reason: "Invalid role")
            }
            if user.role == UserRole.admin.rawValue && newRole != .admin {
                let adminCount = try await User.query(on: database)
                    .filter(\.$role == UserRole.admin.rawValue)
                    .count()
                if adminCount <= 1 {
                    throw Abort(.badRequest, reason: "Cannot demote the last admin account")
                }
            }
            user.role = newRole.rawValue
        }

        try await user.save(on: database)

        if let displayName = payload.displayName {
            if let trainer = try await Trainer.query(on: database).filter(\.$user.$id == id).first() {
                trainer.name = displayName
                try await trainer.save(on: database)
            }
            if let client = try await Client.query(on: database).filter(\.$user.$id == id).first() {
                client.name = displayName
                try await client.save(on: database)
            }
            if let profile = try await Profile.query(on: database).filter(\.$user.$id == id).first() {
                profile.displayName = displayName
                try await profile.save(on: database)
            }
        }

        return try await userDetail(id: id, on: database)
    }

    static func deleteUser(id: UUID, requestedBy: User, on database: any Database) async throws {
        guard let user = try await User.find(id, on: database) else {
            throw Abort(.notFound, reason: "User not found")
        }
        guard user.id != requestedBy.id else {
            throw Abort(.badRequest, reason: "You cannot delete your own account")
        }
        if user.role == UserRole.admin.rawValue {
            let adminCount = try await User.query(on: database)
                .filter(\.$role == UserRole.admin.rawValue)
                .count()
            if adminCount <= 1 {
                throw Abort(.badRequest, reason: "Cannot delete the last admin account")
            }
        }
        try await UserDeletionService.purge(user, on: database)
    }

    static func updateSubscription(
        id: UUID,
        payload: AdminUpdateSubscriptionRequest,
        on database: any Database
    ) async throws -> AdminSubscriptionRowDTO {
        guard let subscription = try await Subscription.find(id, on: database) else {
            throw Abort(.notFound, reason: "Subscription not found")
        }
        if let status = payload.status { subscription.status = status }
        if let expiresAt = payload.expiresAt { subscription.expiresAt = expiresAt }
        if let productID = payload.productID { subscription.productID = productID }
        try await subscription.save(on: database)
        let user = try await subscription.$user.get(on: database)
        return AdminSubscriptionRowDTO(from: subscription, user: user)
    }

    static func createInvite(
        payload: AdminCreateInviteRequest,
        createdBy: User,
        on database: any Database,
        app: Application
    ) async throws -> InviteCreatedResponse {
        guard let trainer = try await Trainer.find(payload.trainerID, on: database) else {
            throw Abort(.notFound, reason: "Trainer not found")
        }

        let invitePayload = CreateInviteRequest(
            trainerID: payload.trainerID,
            expiresInDays: payload.expiresInDays,
            clientEmail: payload.clientEmail,
            clientName: payload.clientName,
            clientPhone: payload.clientPhone,
            sessionsRemaining: payload.sessionsRemaining,
            age: payload.age,
            gender: payload.gender,
            heightCm: payload.heightCm,
            weightKg: payload.weightKg,
            injuryHistory: payload.injuryHistory,
            primaryGoal: payload.primaryGoal,
            skillLevel: payload.skillLevel
        )

        let invite = try await InviteService.createInvite(
            for: trainer,
            createdBy: createdBy,
            expiresInDays: invitePayload.expiresInDays,
            on: database
        )

        var savedClient: Client?
        if let pendingClient = try await InviteService.createPendingClient(
            for: trainer,
            payload: invitePayload,
            on: database
        ) {
            invite.$client.id = try pendingClient.requireID()
            savedClient = pendingClient
        }

        if let rawEmail = invitePayload.clientEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines), !rawEmail.isEmpty {
            invite.invitedEmail = try ClientInviteEmailService.normalizeEmail(rawEmail)
            try await invite.save(on: database)
        } else if savedClient != nil {
            try await invite.save(on: database)
        }

        var emailSent = false
        if let rawEmail = invitePayload.clientEmail, !rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let email = try ClientInviteEmailService.normalizeEmail(rawEmail)
            ClientInviteEmailService.queueInvite(
                to: email,
                trainerName: trainer.name,
                clientName: invitePayload.clientName,
                code: invite.code,
                expiresAt: invite.expiresAt,
                on: app
            )
            emailSent = true
        }

        var smsSent = false
        if let rawPhone = invitePayload.clientPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPhone.isEmpty {
            ClientInviteSMSService.queueInvite(
                to: rawPhone,
                trainerName: trainer.name,
                clientName: invitePayload.clientName,
                code: invite.code,
                userID: savedClient?.$user.id,
                on: app
            )
            smsSent = true
        }

        var clientDTO: ClientDTO?
        if let savedClient {
            clientDTO = try ClientDTO(from: savedClient)
        }

        return InviteCreatedResponse(
            invite: try InviteCodeDTO(from: invite),
            emailSent: emailSent,
            smsSent: smsSent,
            client: clientDTO
        )
    }

    static func deleteInvite(id: UUID, on database: any Database) async throws {
        guard let invite = try await InviteCode.find(id, on: database) else {
            throw Abort(.notFound, reason: "Invite not found")
        }
        if invite.redeemedAt != nil {
            throw Abort(.badRequest, reason: "Cannot delete a redeemed invite")
        }
        try await invite.delete(on: database)
    }

    static func updateSession(
        id: UUID,
        payload: UpdateSessionRequest,
        for user: User,
        on database: any Database,
        app: Application
    ) async throws -> SessionDTO {
        try await SessionService.update(
            sessionID: id,
            for: user,
            payload: payload,
            on: database,
            app: app
        )
    }

    static func deleteSession(
        id: UUID,
        for user: User,
        on database: any Database,
        app: Application
    ) async throws {
        try await SessionService.delete(sessionID: id, for: user, on: database, app: app)
    }

    private static func deleteClientRecords(_ client: Client, on database: any Database) async throws {
        try await ClientDeletionService.delete(client, on: database)
    }

    private static func validatePassword(_ password: String) throws {
        guard password.count >= 8 else {
            throw Abort(.badRequest, reason: "Password must be at least 8 characters")
        }
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }
}

struct AdminUserDetailDTO: Content {
    let user: AdminUserDTO
    let subscription: AdminSubscriptionRowDTO?
    let trainerID: UUID?
    let clientID: UUID?
}

struct AdminCreateUserRequest: Content {
    var email: String
    var password: String
    var role: String
    var displayName: String
    var isEmailVerified: Bool?
    var trainerID: UUID?
    var sessionsRemaining: Int?
}

struct AdminUpdateUserRequest: Content {
    var email: String?
    var displayName: String?
    var role: String?
    var isActive: Bool?
    var isEmailVerified: Bool?
    var password: String?
}

struct AdminUpdateSubscriptionRequest: Content {
    var status: String?
    var expiresAt: Date?
    var productID: String?
}

struct AdminCreateInviteRequest: Content {
    var trainerID: UUID
    var expiresInDays: Int?
    var clientEmail: String?
    var clientName: String?
    var clientPhone: String?
    var sessionsRemaining: Int?
    var age: Int?
    var gender: String?
    var heightCm: Int?
    var weightKg: Int?
    var injuryHistory: String?
    var primaryGoal: String?
    var skillLevel: String?
}

extension AdminSubscriptionRowDTO {
    init(from subscription: Subscription, user: User) {
        self.id = subscription.id!
        self.userID = user.id!
        self.userEmail = user.email
        self.userName = user.displayName
        self.productID = subscription.productID
        self.status = subscription.status
        self.startedAt = subscription.startedAt
        self.expiresAt = subscription.expiresAt
        self.isActive = subscription.status == "active" && (subscription.expiresAt.map { $0 > Date() } ?? true)
        self.createdAt = subscription.createdAt
    }
}
