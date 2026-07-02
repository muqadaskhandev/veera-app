import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ async -> HealthResponse in
        HealthResponse(status: "ok", service: "verra-api")
    }

    try app.register(collection: AuthController())
    try app.register(collection: OnboardingController())
    try app.register(collection: InviteController())
    try app.register(collection: AdminController())
    try app.register(collection: TrainerController())
    try app.register(collection: ClientController())
    try app.register(collection: ProfileController())
    try app.register(collection: HealthController())
    try app.register(collection: SessionController())
    try app.register(collection: ConversationController())

    app.webSocket("ws", "chat") { req, ws in
        await ChatWebSocketHandler.handle(req: req, socket: ws)
    }
}

struct HealthResponse: Content {
    let status: String
    let service: String
}
