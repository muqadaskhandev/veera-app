import Fluent
import Vapor

struct HealthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let health = routes.grouped("api", "health")
        let protected = health.grouped(JWTAuthMiddleware())
        protected.post("sync", use: sync)
        protected.get("me", use: me)
        protected.post("connect", use: connect)
        protected.delete("connect", ":provider", use: disconnect)

        let oura = protected.grouped("oura")
        oura.get("authorize", use: ouraAuthorize)
        oura.post("callback", use: ouraCallback)
        oura.post("sync", use: ouraSync)

        let clients = routes.grouped("api", "clients")
        let protectedClients = clients.grouped(JWTAuthMiddleware())
        protectedClients.get(":clientID", "health", use: clientHealth)
    }

    @Sendable
    func sync(req: Request) async throws -> HealthMeResponse {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(HealthSyncRequest.self)
        return try await HealthService.sync(for: user, payload: payload, on: req.db)
    }

    @Sendable
    func me(req: Request) async throws -> HealthMeResponse {
        let user = try req.auth.require(User.self)
        let days = req.query[Int.self, at: "days"] ?? 30
        return try await HealthService.metrics(for: user, days: days, on: req.db)
    }

    @Sendable
    func connect(req: Request) async throws -> WearableConnectionDTO {
        let user = try req.auth.require(User.self)
        struct ConnectBody: Content { let provider: String }
        let body = try req.content.decode(ConnectBody.self)
        return try await HealthService.connect(for: user, provider: body.provider, on: req.db)
    }

    @Sendable
    func disconnect(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        guard let provider = req.parameters.get("provider") else {
            throw Abort(.badRequest, reason: "Missing provider")
        }
        return try await HealthService.disconnect(for: user, provider: provider, on: req.db)
    }

    @Sendable
    func ouraAuthorize(req: Request) async throws -> OuraAuthorizeResponse {
        let user = try req.auth.require(User.self)
        return try await OuraService.beginAuthorization(for: user, on: req.db, app: req.application)
    }

    @Sendable
    func ouraCallback(req: Request) async throws -> WearableConnectionDTO {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(OuraCallbackRequest.self)
        return try await OuraService.completeAuthorization(
            for: user,
            code: payload.code,
            state: payload.state,
            on: req.db,
            app: req.application
        )
    }

    @Sendable
    func ouraSync(req: Request) async throws -> HealthMeResponse {
        let user = try req.auth.require(User.self)
        let days = req.query[Int.self, at: "days"] ?? 30
        return try await OuraService.sync(for: user, days: days, on: req.db, app: req.application)
    }

    @Sendable
    func clientHealth(req: Request) async throws -> HealthMeResponse {
        let user = try req.auth.require(User.self)
        guard let clientIDString = req.parameters.get("clientID"),
              let clientID = UUID(uuidString: clientIDString) else {
            throw Abort(.badRequest, reason: "Invalid client id")
        }
        let days = req.query[Int.self, at: "days"] ?? 30
        return try await HealthService.metricsForClient(
            clientID: clientID,
            requestedBy: user,
            days: days,
            on: req.db
        )
    }
}
