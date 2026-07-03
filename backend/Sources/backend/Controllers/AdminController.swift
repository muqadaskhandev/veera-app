import Fluent
import Vapor

struct AdminController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let admin = routes.grouped("api", "admin")
            .grouped(JWTAuthMiddleware())
            .grouped(RoleGuardMiddleware(.admin))

        admin.get("dashboard", use: dashboard)
        admin.get("users", use: listUsers)
        admin.post("users", use: createUser)
        admin.get("users", ":userID", use: userDetail)
        admin.patch("users", ":userID", use: updateUser)
        admin.patch("users", ":userID", "status", use: setUserStatus)
        admin.delete("users", ":userID", use: deleteUser)

        admin.get("trainers", use: listTrainers)
        admin.get("clients", use: listClients)
        admin.delete("clients", ":clientID", use: deleteClient)

        admin.get("subscriptions", use: listSubscriptions)
        admin.patch("subscriptions", ":subscriptionID", use: updateSubscription)

        admin.get("sessions", use: listSessions)
        admin.patch("sessions", ":sessionID", use: updateSession)
        admin.delete("sessions", ":sessionID", use: deleteSession)

        admin.get("invites", use: listInvites)
        admin.post("invites", use: createInvite)
        admin.delete("invites", ":inviteID", use: deleteInvite)

        admin.get("exercises", use: listExercises)
        admin.post("exercises", use: createExercise)
        admin.patch("exercises", ":exerciseID", use: updateExercise)
        admin.delete("exercises", ":exerciseID", use: deleteExercise)

        admin.get("notifications", "deliveries", "summary", use: deliverySummary)
        admin.get("notifications", "deliveries", use: listDeliveries)
        admin.post("notifications", "deliveries", ":deliveryID", "retry", use: retryDelivery)
    }

    @Sendable
    func dashboard(req: Request) async throws -> AdminDashboardDTO {
        try await AdminService.dashboard(on: req.db)
    }

    @Sendable
    func listUsers(req: Request) async throws -> [AdminUserDTO] {
        let role = req.query[String.self, at: "role"]
        let search = req.query[String.self, at: "search"]
        let limit = req.query[Int.self, at: "limit"] ?? 100
        return try await AdminService.listUsers(role: role, search: search, limit: limit, on: req.db)
    }

    @Sendable
    func createUser(req: Request) async throws -> AdminUserDetailDTO {
        let payload = try req.content.decode(AdminCreateUserRequest.self)
        return try await AdminService.createUser(payload: payload, on: req.db)
    }

    @Sendable
    func userDetail(req: Request) async throws -> AdminUserDetailDTO {
        guard let userID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid user id")
        }
        return try await AdminService.userDetail(id: userID, on: req.db)
    }

    @Sendable
    func updateUser(req: Request) async throws -> AdminUserDetailDTO {
        guard let userID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid user id")
        }
        let payload = try req.content.decode(AdminUpdateUserRequest.self)
        return try await AdminService.updateUser(id: userID, payload: payload, on: req.db)
    }

    @Sendable
    func setUserStatus(req: Request) async throws -> AdminUserDTO {
        struct StatusRequest: Content { var isActive: Bool }
        guard let user = try await User.find(req.parameters.get("userID"), on: req.db) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(StatusRequest.self)
        user.isActive = payload.isActive
        try await user.save(on: req.db)
        return try AdminUserDTO(from: user)
    }

    @Sendable
    func deleteUser(req: Request) async throws -> HTTPStatus {
        guard let userID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid user id")
        }
        let admin = try req.auth.require(User.self)
        try await AdminService.deleteUser(id: userID, requestedBy: admin, on: req.db)
        return .noContent
    }

    @Sendable
    func listTrainers(req: Request) async throws -> [TrainerDTO] {
        let limit = req.query[Int.self, at: "limit"] ?? 100
        return try await AdminService.listTrainers(limit: limit, on: req.db)
    }

    @Sendable
    func listClients(req: Request) async throws -> [ClientDTO] {
        let limit = req.query[Int.self, at: "limit"] ?? 200
        return try await AdminService.listClients(limit: limit, on: req.db)
    }

    @Sendable
    func deleteClient(req: Request) async throws -> HTTPStatus {
        guard let clientID = req.parameters.get("clientID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid client id")
        }
        try await AdminService.deleteClient(id: clientID, on: req.db)
        return .noContent
    }

    @Sendable
    func listSubscriptions(req: Request) async throws -> [AdminSubscriptionRowDTO] {
        let limit = req.query[Int.self, at: "limit"] ?? 50
        return try await AdminService.listSubscriptions(limit: limit, on: req.db)
    }

    @Sendable
    func updateSubscription(req: Request) async throws -> AdminSubscriptionRowDTO {
        guard let subscriptionID = req.parameters.get("subscriptionID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid subscription id")
        }
        let payload = try req.content.decode(AdminUpdateSubscriptionRequest.self)
        return try await AdminService.updateSubscription(id: subscriptionID, payload: payload, on: req.db)
    }

    @Sendable
    func listSessions(req: Request) async throws -> [AdminSessionRowDTO] {
        let limit = req.query[Int.self, at: "limit"] ?? 30
        return try await AdminService.listRecentSessions(limit: limit, on: req.db)
    }

    @Sendable
    func updateSession(req: Request) async throws -> SessionDTO {
        guard let sessionID = req.parameters.get("sessionID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid session id")
        }
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(UpdateSessionRequest.self)
        return try await AdminService.updateSession(
            id: sessionID,
            payload: payload,
            for: user,
            on: req.db,
            app: req.application
        )
    }

    @Sendable
    func deleteSession(req: Request) async throws -> HTTPStatus {
        guard let sessionID = req.parameters.get("sessionID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid session id")
        }
        let user = try req.auth.require(User.self)
        try await AdminService.deleteSession(id: sessionID, for: user, on: req.db, app: req.application)
        return .noContent
    }

    @Sendable
    func listInvites(req: Request) async throws -> [AdminInviteRowDTO] {
        let limit = req.query[Int.self, at: "limit"] ?? 50
        return try await AdminService.listInvites(limit: limit, on: req.db)
    }

    @Sendable
    func createInvite(req: Request) async throws -> InviteCreatedResponse {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(AdminCreateInviteRequest.self)
        return try await AdminService.createInvite(
            payload: payload,
            createdBy: user,
            on: req.db,
            app: req.application
        )
    }

    @Sendable
    func deleteInvite(req: Request) async throws -> HTTPStatus {
        guard let inviteID = req.parameters.get("inviteID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid invite id")
        }
        try await AdminService.deleteInvite(id: inviteID, on: req.db)
        return .noContent
    }

    @Sendable
    func listExercises(req: Request) async throws -> [ExerciseDTO] {
        let limit = req.query[Int.self, at: "limit"] ?? 100
        return try await AdminService.listExercises(limit: limit, on: req.db)
    }

    @Sendable
    func createExercise(req: Request) async throws -> ExerciseDTO {
        let payload = try req.content.decode(CreateExerciseRequest.self)
        return try await AdminService.createExercise(payload: payload, on: req.db)
    }

    @Sendable
    func updateExercise(req: Request) async throws -> ExerciseDTO {
        guard let exerciseID = req.parameters.get("exerciseID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid exercise id")
        }
        let payload = try req.content.decode(UpdateExerciseRequest.self)
        return try await AdminService.updateExercise(id: exerciseID, payload: payload, on: req.db)
    }

    @Sendable
    func deleteExercise(req: Request) async throws -> HTTPStatus {
        guard let exerciseID = req.parameters.get("exerciseID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid exercise id")
        }
        try await AdminService.deleteExercise(id: exerciseID, on: req.db)
        return .noContent
    }

    @Sendable
    func listDeliveries(req: Request) async throws -> [NotificationOutboxDTO] {
        let status = req.query[String.self, at: "status"]
        let channel = req.query[String.self, at: "channel"]
        let limit = req.query[Int.self, at: "limit"] ?? 50
        return try await NotificationDeliveryService.adminList(
            status: status,
            channel: channel,
            limit: limit,
            on: req.db
        )
    }

    @Sendable
    func deliverySummary(req: Request) async throws -> DeliverySummaryDTO {
        try await NotificationDeliveryService.adminSummary(on: req.db)
    }

    @Sendable
    func retryDelivery(req: Request) async throws -> NotificationOutboxDTO {
        guard let deliveryID = req.parameters.get("deliveryID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid delivery id")
        }
        return try await NotificationDeliveryService.retry(
            outboxID: deliveryID,
            on: req.db,
            app: req.application
        )
    }
}
