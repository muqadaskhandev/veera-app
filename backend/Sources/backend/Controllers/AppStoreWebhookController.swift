import Vapor

struct AppStoreWebhookController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("api", "webhooks", "app-store", "notifications", use: handle)
    }

    /// App Store Server Notifications v2 endpoint.
    /// Configure in App Store Connect: https://your-api-domain/api/webhooks/app-store/notifications
    @Sendable
    func handle(req: Request) async throws -> HTTPStatus {
        let body = req.body.string ?? ""
        req.application.logger.info("App Store notification received (\(body.count) bytes)")

        if let payload = try? req.content.decode(AppStoreNotificationPayload.self) {
            req.application.logger.info("App Store notification type: \(payload.notificationType ?? "unknown")")
        }

        // Full JWS verification and subscription sync can be added here.
        return .ok
    }
}

private struct AppStoreNotificationPayload: Content {
    var signedPayload: String?
    var notificationType: String?
    var subtype: String?

    enum CodingKeys: String, CodingKey {
        case signedPayload
        case notificationType
        case subtype
    }
}
