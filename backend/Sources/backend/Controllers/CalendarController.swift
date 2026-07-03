import Fluent
import Vapor

struct CalendarController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        // Public — Google redirects here (http/https only); we bounce into the iOS app deep link.
        routes.grouped("api", "calendar", "google")
            .get("oauth", "callback", use: oauthBridge)

        let google = routes.grouped("api", "calendar", "google")
            .grouped(JWTAuthMiddleware())

        google.get("status", use: status)
        google.get("authorize", use: authorize)
        google.post("callback", use: callback)
        google.delete(use: disconnect)
        google.get("busy-blocks", use: busyBlocks)
        google.post("export", use: exportOne)
        google.post("export-all", use: exportAll)
        google.delete("export", ":sessionID", use: deleteExport)
    }

    @Sendable
    func oauthBridge(req: Request) async throws -> Response {
        let appCallback = GoogleCalendarService.appCallbackURI(on: req.application)
        guard var components = URLComponents(string: appCallback) else {
            throw Abort(.internalServerError, reason: "Invalid app callback URI")
        }

        var items: [URLQueryItem] = []
        for name in ["code", "state", "error", "error_description"] {
            if let value = req.query[String.self, at: name] {
                items.append(URLQueryItem(name: name, value: value))
            }
        }
        components.queryItems = items.isEmpty ? nil : items

        guard let target = components.url?.absoluteString else {
            throw Abort(.internalServerError, reason: "Failed to build app callback URL")
        }
        return req.redirect(to: target)
    }

    @Sendable
    func status(req: Request) async throws -> GoogleCalendarStatusResponse {
        let user = try req.auth.require(User.self)
        return try await GoogleCalendarService.status(for: user, on: req.db, app: req.application)
    }

    @Sendable
    func authorize(req: Request) async throws -> GoogleCalendarAuthorizeResponse {
        let user = try req.auth.require(User.self)
        return try await GoogleCalendarService.beginAuthorization(for: user, on: req.db, app: req.application)
    }

    @Sendable
    func callback(req: Request) async throws -> GoogleCalendarStatusResponse {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(GoogleCalendarCallbackRequest.self)
        return try await GoogleCalendarService.completeAuthorization(
            for: user,
            code: payload.code,
            state: payload.state,
            on: req.db,
            app: req.application
        )
    }

    @Sendable
    func disconnect(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        return try await GoogleCalendarService.disconnect(for: user, on: req.db)
    }

    @Sendable
    func busyBlocks(req: Request) async throws -> [BusyBlockDTO] {
        let user = try req.auth.require(User.self)
        guard let fromString = req.query[String.self, at: "from"],
              let toString = req.query[String.self, at: "to"],
              let from = parseISO8601(fromString),
              let to = parseISO8601(toString) else {
            throw Abort(.badRequest, reason: "Missing or invalid from/to query parameters (ISO-8601)")
        }
        return try await GoogleCalendarService.fetchBusyBlocks(
            for: user,
            from: from,
            to: to,
            on: req.db,
            app: req.application
        )
    }

    @Sendable
    func exportOne(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(GoogleCalendarExportRequest.self)
        try await GoogleCalendarService.exportSession(
            for: user,
            payload: payload,
            on: req.db,
            app: req.application
        )
        return .ok
    }

    @Sendable
    func exportAll(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(GoogleCalendarExportAllRequest.self)
        try await GoogleCalendarService.exportAllSessions(
            for: user,
            payload: payload,
            on: req.db,
            app: req.application
        )
        return .ok
    }

    @Sendable
    func deleteExport(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        guard let sessionIDString = req.parameters.get("sessionID"),
              let sessionID = UUID(uuidString: sessionIDString) else {
            throw Abort(.badRequest, reason: "Invalid session id")
        }
        try await GoogleCalendarService.deleteExportedSession(
            for: user,
            sessionID: sessionID,
            on: req.db,
            app: req.application
        )
        return .noContent
    }

    private func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
