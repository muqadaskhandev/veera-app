import Fluent
import Foundation
import Vapor

enum OuraService {
    private static let authorizeURL = "https://cloud.ouraring.com/oauth/authorize"
    private static let tokenURL = "https://api.ouraring.com/oauth/token"
    private static let apiBase = "https://api.ouraring.com/v2/usercollection"
    private static let scopes = "daily personal"

    struct TokenForm: Content {
        let grant_type: String
        let code: String?
        let refresh_token: String?
        let redirect_uri: String?
        let client_id: String
        let client_secret: String
    }

    struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
        let scope: String?
        let token_type: String?
    }

    struct CollectionEnvelope<T: Decodable>: Decodable {
        let data: [T]
        let next_token: String?
    }

    struct DailySleep: Decodable {
        let day: String
        let total_sleep_duration: Int?
    }

    struct DailyActivity: Decodable {
        let day: String
        let steps: Int?
        let active_calories: Int?
    }

    struct DailyReadiness: Decodable {
        let day: String
        let resting_heart_rate: Int?
    }

    struct SleepSession: Decodable {
        let day: String
        let average_hrv: Double?
    }

    static func isConfigured() -> Bool {
        guard let clientID = Environment.get("OURA_CLIENT_ID"),
              let clientSecret = Environment.get("OURA_CLIENT_SECRET"),
              !clientID.isEmpty, !clientSecret.isEmpty else {
            return false
        }
        return true
    }

    /// When true, Oura connect/sync uses sample data — no Oura account or API keys needed.
    static func isDevMode(on app: Application) -> Bool {
        if Environment.get("OURA_DEV_MODE")?.lowercased() == "true" {
            return true
        }
        return app.environment == .development && !isConfigured()
    }

    static func status(on app: Application) -> OuraStatusResponse {
        OuraStatusResponse(configured: isConfigured(), devMode: isDevMode(on: app))
    }

    private static let devTokenMarker = "verra-dev"

    static func devConnect(for user: User, on database: any Database, app: Application) async throws -> WearableConnectionDTO {
        guard isDevMode(on: app) else {
            throw Abort(.forbidden, reason: "Oura dev mode is not enabled")
        }
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }

        let expiresAt = Date().addingTimeInterval(365 * 24 * 60 * 60)
        if let existing = try await OuraToken.query(on: database)
            .filter(\.$user.$id == userID)
            .first() {
            existing.accessToken = devTokenMarker
            existing.refreshToken = devTokenMarker
            existing.expiresAt = expiresAt
            existing.scope = scopes
            try await existing.save(on: database)
        } else {
            let token = OuraToken(
                userID: userID,
                accessToken: devTokenMarker,
                refreshToken: devTokenMarker,
                expiresAt: expiresAt,
                scope: scopes
            )
            try await token.save(on: database)
        }

        app.logger.info("Oura dev mode: connected sample data source for user \(userID)")
        return try await HealthService.connect(for: user, provider: WearableProvider.oura.rawValue, on: database)
    }

    static func redirectURI(on app: Application) -> String {
        Environment.get("OURA_REDIRECT_URI")
            ?? "app.rork.hiyjy25oz4yjrbssyotkw://oura/callback"
    }

    static func beginAuthorization(for user: User, on database: any Database, app: Application) async throws -> OuraAuthorizeResponse {
        guard isConfigured() else {
            throw Abort(.serviceUnavailable, reason: "Oura is not configured on the server")
        }
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }

        let state = UUID().uuidString
        let expiresAt = Date().addingTimeInterval(600)
        try await OuraOAuthState.query(on: database)
            .filter(\.$user.$id == userID)
            .delete()
        try await OuraOAuthState(userID: userID, state: state, expiresAt: expiresAt).save(on: database)

        let redirectURI = redirectURI(on: app)
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Environment.get("OURA_CLIENT_ID")),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
        ]

        guard let url = components.url?.absoluteString else {
            throw Abort(.internalServerError, reason: "Failed to build Oura authorization URL")
        }

        return OuraAuthorizeResponse(authorizationURL: url, state: state, redirectURI: redirectURI)
    }

    static func completeAuthorization(
        for user: User,
        code: String,
        state: String,
        on database: any Database,
        app: Application
    ) async throws -> WearableConnectionDTO {
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }

        guard let oauthState = try await OuraOAuthState.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$state == state)
            .first(),
            oauthState.expiresAt > Date() else {
            throw Abort(.badRequest, reason: "Invalid or expired Oura authorization state")
        }

        try await oauthState.delete(on: database)

        let redirectURI = redirectURI(on: app)
        let tokenResponse = try await exchangeCode(code: code, redirectURI: redirectURI, on: app)
        try await saveToken(tokenResponse, for: userID, on: database)
        return try await HealthService.connect(for: user, provider: WearableProvider.oura.rawValue, on: database)
    }

    static func sync(for user: User, days: Int = 30, on database: any Database, app: Application) async throws -> HealthMeResponse {
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }

        if try await isDevConnection(for: userID, on: database) {
            let metrics = sampleMetrics(days: days)
            let payload = HealthSyncRequest(provider: WearableProvider.oura.rawValue, metrics: metrics)
            return try await HealthService.sync(for: user, payload: payload, on: database)
        }

        let token = try await validAccessToken(for: userID, on: database, app: app)
        let start = HealthDateCodec.dayString(from: HealthDateCodec.daysAgo(days - 1))
        let end = HealthDateCodec.dayString(from: Date())

        async let sleepRows = fetchCollection(DailySleep.self, path: "daily_sleep", start: start, end: end, token: token, app: app)
        async let activityRows = fetchCollection(DailyActivity.self, path: "daily_activity", start: start, end: end, token: token, app: app)
        async let readinessRows = fetchCollection(DailyReadiness.self, path: "daily_readiness", start: start, end: end, token: token, app: app)
        async let hrvRows = fetchCollection(SleepSession.self, path: "sleep", start: start, end: end, token: token, app: app)

        let merged = try await mergeMetrics(
            sleep: sleepRows,
            activity: activityRows,
            readiness: readinessRows,
            hrvSessions: hrvRows
        )

        let payload = HealthSyncRequest(provider: WearableProvider.oura.rawValue, metrics: merged)
        return try await HealthService.sync(for: user, payload: payload, on: database)
    }

    static func revoke(for userID: UUID, on database: any Database) async throws {
        try await OuraToken.query(on: database)
            .filter(\.$user.$id == userID)
            .delete()
        try await OuraOAuthState.query(on: database)
            .filter(\.$user.$id == userID)
            .delete()
    }

    // MARK: - Token management

    private static func saveToken(_ response: TokenResponse, for userID: UUID, on database: any Database) async throws {
        guard let refreshToken = response.refresh_token else {
            throw Abort(.badRequest, reason: "Oura did not return a refresh token")
        }
        let expiresIn = response.expires_in ?? (30 * 24 * 60 * 60)
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))

        if let existing = try await OuraToken.query(on: database)
            .filter(\.$user.$id == userID)
            .first() {
            existing.accessToken = response.access_token
            existing.refreshToken = refreshToken
            existing.expiresAt = expiresAt
            existing.scope = response.scope ?? scopes
            try await existing.save(on: database)
        } else {
            let token = OuraToken(
                userID: userID,
                accessToken: response.access_token,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                scope: response.scope ?? scopes
            )
            try await token.save(on: database)
        }
    }

    private static func validAccessToken(for userID: UUID, on database: any Database, app: Application) async throws -> String {
        guard let stored = try await OuraToken.query(on: database)
            .filter(\.$user.$id == userID)
            .first() else {
            throw Abort(.badRequest, reason: "Oura is not connected")
        }

        if stored.accessToken == devTokenMarker {
            return stored.accessToken
        }

        if stored.expiresAt > Date().addingTimeInterval(120) {
            return stored.accessToken
        }

        let refreshed = try await refreshToken(stored.refreshToken, on: app)
        stored.accessToken = refreshed.access_token
        if let newRefresh = refreshed.refresh_token {
            stored.refreshToken = newRefresh
        }
        let expiresIn = refreshed.expires_in ?? (30 * 24 * 60 * 60)
        stored.expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        if let scope = refreshed.scope {
            stored.scope = scope
        }
        try await stored.save(on: database)
        return stored.accessToken
    }

    private static func exchangeCode(code: String, redirectURI: String, on app: Application) async throws -> TokenResponse {
        try await requestToken(
            TokenForm(
                grant_type: "authorization_code",
                code: code,
                refresh_token: nil,
                redirect_uri: redirectURI,
                client_id: try requireClientID(),
                client_secret: try requireClientSecret()
            ),
            on: app
        )
    }

    private static func refreshToken(_ refreshToken: String, on app: Application) async throws -> TokenResponse {
        try await requestToken(
            TokenForm(
                grant_type: "refresh_token",
                code: nil,
                refresh_token: refreshToken,
                redirect_uri: nil,
                client_id: try requireClientID(),
                client_secret: try requireClientSecret()
            ),
            on: app
        )
    }

    private static func requestToken(_ form: TokenForm, on app: Application) async throws -> TokenResponse {
        let response = try await app.client.post(URI(string: tokenURL)) { req in
            req.headers.contentType = .urlEncodedForm
            try req.content.encode(form)
        }

        guard response.status == .ok else {
            let body = response.body.map { String(buffer: $0) } ?? ""
            app.logger.error("Oura token request failed: \(response.status) \(body)")
            throw Abort(.badGateway, reason: "Oura token exchange failed")
        }

        return try response.content.decode(TokenResponse.self)
    }

    // MARK: - Data fetch

    private static func fetchCollection<T: Decodable>(
        _ type: T.Type,
        path: String,
        start: String,
        end: String,
        token: String,
        app: Application
    ) async throws -> [T] {
        var results: [T] = []
        var nextToken: String?

        repeat {
            var components = URLComponents(string: "\(apiBase)/\(path)")!
            var query = [
                URLQueryItem(name: "start_date", value: start),
                URLQueryItem(name: "end_date", value: "\(end)T23:59:59"),
            ]
            if let nextToken {
                query.append(URLQueryItem(name: "next_token", value: nextToken))
            }
            components.queryItems = query

            let response = try await app.client.get(URI(string: components.url!.absoluteString)) { req in
                req.headers.bearerAuthorization = .init(token: token)
            }

            guard response.status == .ok else {
                let body = response.body.map { String(buffer: $0) } ?? ""
                app.logger.error("Oura API \(path) failed: \(response.status) \(body)")
                throw Abort(.badGateway, reason: "Failed to fetch data from Oura")
            }

            let envelope = try response.content.decode(CollectionEnvelope<T>.self)
            results.append(contentsOf: envelope.data)
            nextToken = envelope.next_token
        } while nextToken != nil

        return results
    }

    private static func mergeMetrics(
        sleep: [DailySleep],
        activity: [DailyActivity],
        readiness: [DailyReadiness],
        hrvSessions: [SleepSession]
    ) -> [HealthDailyMetricInput] {
        struct DayValues {
            var sleepMinutes: Int?
            var steps: Int?
            var restingHR: Int?
            var hrv: Double?
            var activeCalories: Int?
        }

        var byDay: [String: DayValues] = [:]

        func ensureDay(_ day: String) {
            if byDay[day] == nil {
                byDay[day] = DayValues()
            }
        }

        for row in sleep {
            ensureDay(row.day)
            if let seconds = row.total_sleep_duration {
                byDay[row.day]?.sleepMinutes = max(0, seconds / 60)
            }
        }

        for row in activity {
            ensureDay(row.day)
            byDay[row.day]?.steps = row.steps
            byDay[row.day]?.activeCalories = row.active_calories
        }

        for row in readiness {
            ensureDay(row.day)
            byDay[row.day]?.restingHR = row.resting_heart_rate
        }

        var hrvByDay: [String: [Double]] = [:]
        for row in hrvSessions {
            if let hrv = row.average_hrv {
                hrvByDay[row.day, default: []].append(hrv)
            }
        }
        for (day, values) in hrvByDay {
            ensureDay(day)
            byDay[day]?.hrv = values.reduce(0, +) / Double(values.count)
        }

        return byDay.keys.sorted().map { day in
            let values = byDay[day]!
            return HealthDailyMetricInput(
                date: day,
                sleepMinutes: values.sleepMinutes,
                steps: values.steps,
                restingHR: values.restingHR,
                hrv: values.hrv,
                activeCalories: values.activeCalories
            )
        }
    }

    private static func isDevConnection(for userID: UUID, on database: any Database) async throws -> Bool {
        guard let token = try await OuraToken.query(on: database)
            .filter(\.$user.$id == userID)
            .first() else {
            return false
        }
        return token.accessToken == devTokenMarker
    }

    private static func sampleMetrics(days: Int) -> [HealthDailyMetricInput] {
        (0..<days).map { offset in
            let day = HealthDateCodec.dayString(from: HealthDateCodec.daysAgo((days - 1) - offset))
            return HealthDailyMetricInput(
                date: day,
                sleepMinutes: 420 + (offset % 5) * 15,
                steps: 8_000 + (offset % 7) * 300,
                restingHR: 54 + (offset % 4),
                hrv: 45 + Double(offset % 6),
                activeCalories: 350 + (offset % 5) * 20
            )
        }
    }

    private static func requireClientID() throws -> String {
        guard let value = Environment.get("OURA_CLIENT_ID"), !value.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "OURA_CLIENT_ID is not configured")
        }
        return value
    }

    private static func requireClientSecret() throws -> String {
        guard let value = Environment.get("OURA_CLIENT_SECRET"), !value.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "OURA_CLIENT_SECRET is not configured")
        }
        return value
    }
}
