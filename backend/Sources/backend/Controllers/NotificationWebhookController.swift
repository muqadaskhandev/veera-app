import Fluent
import Foundation
import Vapor

struct NotificationWebhookController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("api", "webhooks", "twilio", "sms-status", use: twilioSMSStatus)
    }

    /// Twilio delivery status callback (sent, delivered, failed, undelivered).
    @Sendable
    func twilioSMSStatus(req: Request) async throws -> HTTPStatus {
        let payload = try parseTwilioForm(from: req)
        let messageSID = payload["MessageSid"] ?? payload["SmsSid"]
        let status = payload["MessageStatus"] ?? payload["SmsStatus"] ?? "unknown"
        let errorMessage = payload["ErrorMessage"]

        guard let messageSID else {
            throw Abort(.badRequest, reason: "Missing MessageSid")
        }

        await NotificationDeliveryService.applyTwilioStatus(
            messageSID: messageSID,
            status: status,
            errorMessage: errorMessage,
            on: req.db,
            app: req.application
        )

        return .ok
    }

    private func parseTwilioForm(from req: Request) throws -> [String: String] {
        if let decoded = try? req.content.decode(TwilioStatusCallback.self) {
            return [
                "MessageSid": decoded.messageSid,
                "MessageStatus": decoded.messageStatus,
                "ErrorMessage": decoded.errorMessage,
            ].compactMapValues { $0 }
        }

        guard let body = req.body.string else { return [:] }
        var values: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            values[key] = value
        }
        return values
    }
}

private struct TwilioStatusCallback: Content {
    var messageSid: String?
    var messageStatus: String?
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case messageSid = "MessageSid"
        case messageStatus = "MessageStatus"
        case errorMessage = "ErrorMessage"
    }
}
