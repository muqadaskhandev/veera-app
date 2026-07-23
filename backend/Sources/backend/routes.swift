import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ async -> HealthResponse in
        HealthResponse(status: "ok", service: "verra-api")
    }

    try app.register(collection: AccountController())
    try app.register(collection: AuthController())
    try app.register(collection: OnboardingController())
    try app.register(collection: InviteController())
    try app.register(collection: AdminController())
    try app.register(collection: AdminUIController())
    try app.register(collection: TrainerController())
    try app.register(collection: ClientController())
    try app.register(collection: ProfileController())
    try app.register(collection: HealthController())
    try app.register(collection: SessionController())
    try app.register(collection: ConversationController())
    try app.register(collection: FinancialController())
    try app.register(collection: ClientProfileController())
    try app.register(collection: NotificationController())
    try app.register(collection: ExerciseController())
    try app.register(collection: SubscriptionController())
    try app.register(collection: PaymentController())
    try app.register(collection: StripeWebhookController())
    try app.register(collection: AppStoreWebhookController())
    try app.register(collection: StorageController())
    try app.register(collection: NotificationWebhookController())
    try app.register(collection: CalendarController())
    try app.register(collection: JoinLandingController())

    app.webSocket("ws", "chat") { req, ws in
        await ChatWebSocketHandler.handle(req: req, socket: ws)
    }
}

struct HealthResponse: Content {
    let status: String
    let service: String
}
