import Fluent
import Vapor

struct PaymentController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let payments = routes.grouped("api", "payments")
            .grouped(JWTAuthMiddleware())

        payments.get("config", use: config)
        payments.post("intent", use: createIntent)
        payments.get("intent", ":paymentIntentID", use: status)
    }

    @Sendable
    func config(req: Request) async throws -> PaymentConfigDTO {
        StripeService.config()
    }

    @Sendable
    func createIntent(req: Request) async throws -> PaymentIntentDTO {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(CreatePaymentIntentRequest.self)
        return try await StripeService.createPaymentIntent(
            for: user,
            payload: payload,
            on: req.db,
            app: req.application
        )
    }

    @Sendable
    func status(req: Request) async throws -> PaymentStatusDTO {
        let user = try req.auth.require(User.self)
        guard let paymentIntentID = req.parameters.get("paymentIntentID") else {
            throw Abort(.badRequest, reason: "Invalid payment intent id")
        }
        return try await StripeService.paymentStatus(
            paymentIntentID: paymentIntentID,
            for: user,
            on: req.db,
            app: req.application
        )
    }
}
