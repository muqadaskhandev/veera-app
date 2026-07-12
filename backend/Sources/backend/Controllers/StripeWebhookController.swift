import Fluent
import Vapor

struct StripeWebhookController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("api", "webhooks", "stripe", use: handle)
    }

    @Sendable
    func handle(req: Request) async throws -> HTTPStatus {
        guard let body = req.body.data else {
            throw Abort(.badRequest, reason: "Missing webhook body")
        }

        try await StripeService.handleWebhook(
            payload: body,
            signatureHeader: req.headers.first(name: "Stripe-Signature"),
            on: req.db,
            app: req.application
        )

        return .ok
    }
}
