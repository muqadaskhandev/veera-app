import Fluent
import Vapor

struct SessionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let sessions = routes.grouped("api", "sessions")
            .grouped(JWTAuthMiddleware())

        sessions.get(use: index)
        sessions.post(use: create)
        sessions.get(":sessionID", use: show)
        sessions.patch(":sessionID", use: update)
        sessions.delete(":sessionID", use: delete)
    }

    @Sendable
    func index(req: Request) async throws -> [SessionDTO] {
        let user = try req.auth.require(User.self)
        return try await SessionService.list(
            for: user,
            from: req.query[Date.self, at: "from"],
            to: req.query[Date.self, at: "to"],
            on: req.db
        )
    }

    @Sendable
    func show(req: Request) async throws -> SessionDTO {
        let user = try req.auth.require(User.self)
        guard let sessionID = req.parameters.get("sessionID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid session id")
        }
        let sessions = try await SessionService.list(for: user, from: nil, to: nil, on: req.db)
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            throw Abort(.notFound)
        }
        return session
    }

    @Sendable
    func create(req: Request) async throws -> SessionDTO {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(CreateSessionRequest.self)
        return try await SessionService.create(for: user, payload: payload, on: req.db, app: req.application)
    }

    @Sendable
    func update(req: Request) async throws -> SessionDTO {
        let user = try req.auth.require(User.self)
        guard let sessionID = req.parameters.get("sessionID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid session id")
        }
        let payload = try req.content.decode(UpdateSessionRequest.self)
        return try await SessionService.update(
            sessionID: sessionID,
            for: user,
            payload: payload,
            on: req.db,
            app: req.application
        )
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        guard let sessionID = req.parameters.get("sessionID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid session id")
        }
        try await SessionService.delete(sessionID: sessionID, for: user, on: req.db, app: req.application)
        return .noContent
    }
}

struct FinancialController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let financials = routes.grouped("api", "financials")
            .grouped(JWTAuthMiddleware())

        let trainerFinancials = financials.grouped(RoleGuardMiddleware(.trainer, .admin))
        trainerFinancials.get(use: summary)
        trainerFinancials.post(use: create)

        financials.get("clients", ":clientID", use: clientLedger)
    }

    @Sendable
    func summary(req: Request) async throws -> FinancialSummaryDTO {
        let user = try req.auth.require(User.self)
        let filter = req.query[String.self, at: "filter"] ?? "month"
        return try await FinancialService.summary(for: user, filter: filter, on: req.db)
    }

    @Sendable
    func create(req: Request) async throws -> FinancialEventDTO {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(CreateFinancialEventRequest.self)
        return try await FinancialService.createEvent(for: user, payload: payload, on: req.db, app: req.application)
    }

    @Sendable
    func clientLedger(req: Request) async throws -> [FinancialEventDTO] {
        let user = try req.auth.require(User.self)
        guard let clientID = req.parameters.get("clientID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid client id")
        }
        return try await FinancialService.clientLedger(clientID: clientID, for: user, on: req.db)
    }
}

struct ClientProfileController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let clients = routes.grouped("api", "clients")
            .grouped(JWTAuthMiddleware())

        clients.get(":clientID", "workouts", use: getWorkoutWeek)
        clients.put(":clientID", "workouts", ":week", use: saveWorkoutWeek)
        clients.get(":clientID", "weight", use: weightLogs)
        clients.post(":clientID", "weight", use: logWeight)
        clients.get(":clientID", "photos", use: photos)
        clients.on(.POST, ":clientID", "photos", body: .collect(maxSize: "12mb"), use: uploadPhoto)
        clients.delete(":clientID", "photos", ":photoID", use: deletePhoto)
        clients.get(":clientID", "nutrition", use: nutrition)
        clients.patch(":clientID", "nutrition", use: updateNutrition)
    }

    @Sendable
    func getWorkoutWeek(req: Request) async throws -> WorkoutWeekResponse {
        let user = try req.auth.require(User.self)
        guard let clientID = req.parameters.get("clientID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let week = req.query[Int.self, at: "week"] ?? 0
        return try await WorkoutService.week(for: clientID, weekIndex: week, user: user, on: req.db)
    }

    @Sendable
    func saveWorkoutWeek(req: Request) async throws -> WorkoutWeekResponse {
        let user = try req.auth.require(User.self)
        guard let clientID = req.parameters.get("clientID", as: UUID.self),
              let week = req.parameters.get("week", as: Int.self) else {
            throw Abort(.badRequest)
        }
        let payload = try req.content.decode(SaveWorkoutWeekRequest.self)
        return try await WorkoutService.saveWeek(
            clientID: clientID,
            weekIndex: week,
            payload: payload,
            user: user,
            on: req.db
        )
    }

    @Sendable
    func weightLogs(req: Request) async throws -> [WeightLogDTO] {
        let user = try req.auth.require(User.self)
        guard let clientID = req.parameters.get("clientID", as: UUID.self) else { throw Abort(.badRequest) }
        return try await ClientProfileService.weightLogs(clientID: clientID, user: user, on: req.db)
    }

    @Sendable
    func logWeight(req: Request) async throws -> WeightLogDTO {
        let user = try req.auth.require(User.self)
        guard let clientID = req.parameters.get("clientID", as: UUID.self) else { throw Abort(.badRequest) }
        let payload = try req.content.decode(LogWeightRequest.self)
        return try await ClientProfileService.logWeight(clientID: clientID, payload: payload, user: user, on: req.db, app: req.application)
    }

    @Sendable
    func photos(req: Request) async throws -> [ProgressPhotoDTO] {
        let user = try req.auth.require(User.self)
        guard let clientID = req.parameters.get("clientID", as: UUID.self) else { throw Abort(.badRequest) }
        return try await ClientProfileService.photos(clientID: clientID, user: user, on: req.db, app: req.application)
    }

    @Sendable
    func uploadPhoto(req: Request) async throws -> ProgressPhotoDTO {
        let user = try req.auth.require(User.self)
        guard let clientID = req.parameters.get("clientID", as: UUID.self) else { throw Abort(.badRequest) }
        struct PhotoUpload: Content { var photo: File }
        let upload = try req.content.decode(PhotoUpload.self)
        let capturedAt = req.query[Date.self, at: "capturedAt"]
        return try await ClientProfileService.addPhoto(
            clientID: clientID,
            file: upload.photo,
            capturedAt: capturedAt,
            user: user,
            on: req.db,
            app: req.application
        )
    }

    @Sendable
    func deletePhoto(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        guard let clientID = req.parameters.get("clientID", as: UUID.self),
              let photoID = req.parameters.get("photoID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        try await ClientProfileService.deletePhoto(
            clientID: clientID,
            photoID: photoID,
            user: user,
            on: req.db,
            app: req.application
        )
        return .noContent
    }

    @Sendable
    func nutrition(req: Request) async throws -> NutritionProfileDTO {
        let user = try req.auth.require(User.self)
        guard let clientID = req.parameters.get("clientID", as: UUID.self) else { throw Abort(.badRequest) }
        return try await ClientProfileService.nutrition(clientID: clientID, user: user, on: req.db)
    }

    @Sendable
    func updateNutrition(req: Request) async throws -> NutritionProfileDTO {
        let user = try req.auth.require(User.self)
        guard let clientID = req.parameters.get("clientID", as: UUID.self) else { throw Abort(.badRequest) }
        let payload = try req.content.decode(UpdateNutritionRequest.self)
        return try await ClientProfileService.updateNutrition(
            clientID: clientID,
            payload: payload,
            user: user,
            on: req.db
        )
    }
}

struct NotificationController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let notifications = routes.grouped("api", "notifications")
            .grouped(JWTAuthMiddleware())

        notifications.get(use: index)
        notifications.patch("read-all", use: markAllRead)
        notifications.patch(":notificationID", "read", use: markRead)
        notifications.get("preferences", use: getPreferences)
        notifications.patch("preferences", use: updatePreferences)
    }

    @Sendable
    func index(req: Request) async throws -> [UserNotificationDTO] {
        let user = try req.auth.require(User.self)
        return try await NotificationService.list(for: user, on: req.db)
    }

    @Sendable
    func markRead(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        guard let notificationID = req.parameters.get("notificationID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        try await NotificationService.markRead(notificationID: notificationID, for: user, on: req.db)
        return .noContent
    }

    @Sendable
    func markAllRead(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        try await NotificationService.markAllRead(for: user, on: req.db)
        return .noContent
    }

    @Sendable
    func getPreferences(req: Request) async throws -> NotificationPreferencesDTO {
        let user = try req.auth.require(User.self)
        let prefs = try await NotificationService.preferences(for: user, on: req.db)
        return NotificationPreferencesDTO(from: prefs)
    }

    @Sendable
    func updatePreferences(req: Request) async throws -> NotificationPreferencesDTO {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(UpdateNotificationPreferencesRequest.self)
        return try await NotificationService.updatePreferences(for: user, payload: payload, on: req.db)
    }
}

struct ExerciseController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let exercises = routes.grouped("api", "exercises")
            .grouped(JWTAuthMiddleware())

        exercises.get("categories", use: categories)
        exercises.get(use: index)
        exercises.get(":exerciseID", use: show)

        let managed = exercises.grouped(RoleGuardMiddleware(.trainer, .admin))
        managed.post(use: create)
        managed.patch(":exerciseID", use: update)
        managed.on(.POST, ":exerciseID", "image", body: .collect(maxSize: "12mb"), use: uploadImage)
        managed.on(.POST, ":exerciseID", "video", body: .collect(maxSize: "64mb"), use: uploadVideo)
    }

    @Sendable
    func categories(req: Request) async throws -> [String] {
        ExerciseService.categories()
    }

    @Sendable
    func index(req: Request) async throws -> [ExerciseDTO] {
        let query = req.query[String.self, at: "q"]
        let category = req.query[String.self, at: "category"]
        let limit = req.query[Int.self, at: "limit"] ?? 30
        return try await ExerciseService.list(
            query: query,
            category: category,
            limit: limit,
            on: req.db,
            baseURL: Environment.get("APP_URL")
        )
    }

    @Sendable
    func show(req: Request) async throws -> ExerciseDTO {
        guard let exerciseID = req.parameters.get("exerciseID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid exercise id")
        }
        return try await ExerciseService.show(
            id: exerciseID,
            on: req.db,
            baseURL: Environment.get("APP_URL")
        )
    }

    @Sendable
    func create(req: Request) async throws -> ExerciseDTO {
        let payload = try req.content.decode(CreateExerciseRequest.self)
        return try await ExerciseService.create(
            payload: payload,
            on: req.db,
            baseURL: Environment.get("APP_URL")
        )
    }

    @Sendable
    func update(req: Request) async throws -> ExerciseDTO {
        guard let exerciseID = req.parameters.get("exerciseID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid exercise id")
        }
        let payload = try req.content.decode(UpdateExerciseRequest.self)
        return try await ExerciseService.update(
            id: exerciseID,
            payload: payload,
            on: req.db,
            baseURL: Environment.get("APP_URL")
        )
    }

    @Sendable
    func uploadImage(req: Request) async throws -> ExerciseDTO {
        guard let exerciseID = req.parameters.get("exerciseID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid exercise id")
        }
        struct ImageUpload: Content { var image: File }
        let upload = try req.content.decode(ImageUpload.self)
        return try await ExerciseService.uploadImage(
            id: exerciseID,
            file: upload.image,
            on: req.db,
            app: req.application,
            baseURL: Environment.get("APP_URL")
        )
    }

    @Sendable
    func uploadVideo(req: Request) async throws -> ExerciseDTO {
        guard let exerciseID = req.parameters.get("exerciseID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid exercise id")
        }
        struct VideoUpload: Content { var video: File }
        let upload = try req.content.decode(VideoUpload.self)
        return try await ExerciseService.uploadVideo(
            id: exerciseID,
            file: upload.video,
            on: req.db,
            app: req.application,
            baseURL: Environment.get("APP_URL")
        )
    }
}

struct SubscriptionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let subscriptions = routes.grouped("api", "subscriptions")
            .grouped(JWTAuthMiddleware())

        subscriptions.get("me", use: current)
        subscriptions.post("validate", use: validate)
    }

    @Sendable
    func current(req: Request) async throws -> SubscriptionDTO {
        let user = try req.auth.require(User.self)
        guard user.userRole == .trainer || user.userRole == .admin else {
            throw Abort(.forbidden, reason: "Subscriptions are only available for trainers")
        }
        guard let subscription = try await SubscriptionService.current(for: user, on: req.db) else {
            throw Abort(.notFound, reason: "No subscription on file")
        }
        return subscription
    }

    @Sendable
    func validate(req: Request) async throws -> SubscriptionDTO {
        let user = try req.auth.require(User.self)
        guard user.userRole == .trainer || user.userRole == .admin else {
            throw Abort(.forbidden, reason: "Subscriptions are only available for trainers")
        }
        let payload = try req.content.decode(ValidateReceiptRequest.self)
        return try await SubscriptionService.validateReceipt(
            for: user,
            payload: payload,
            on: req.db,
            app: req.application
        )
    }
}

struct StorageController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("api", "storage", ":folder", ":filename", use: serve)
    }

    @Sendable
    func serve(req: Request) async throws -> Response {
        guard let folder = req.parameters.get("folder"),
              let filename = req.parameters.get("filename") else {
            throw Abort(.badRequest)
        }
        guard let path = StorageService.localFilePath(storedPath: filename, folder: folder, on: req.application) else {
            throw Abort(.notFound)
        }
        return try await req.fileio.asyncStreamFile(at: path)
    }
}
