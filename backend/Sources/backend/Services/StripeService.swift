import Crypto
import Fluent
import Foundation
import Vapor

enum StripeService {
    static let trainerMonthlyProductID = "app.rork.hiyjy25oz4yjrbssyotkw.trainer.monthly"
    static let trainerAnnualProductID = "app.rork.hiyjy25oz4yjrbssyotkw.trainer.annual"

    static func isConfigured() -> Bool {
        guard let key = Environment.get("STRIPE_SECRET_KEY"), !key.isEmpty else { return false }
        return true
    }

    static func publishableKey() -> String? {
        Environment.get("STRIPE_PUBLISHABLE_KEY").flatMap { $0.isEmpty ? nil : $0 }
    }

    static func merchantID() -> String? {
        Environment.get("APPLE_PAY_MERCHANT_ID").flatMap { $0.isEmpty ? nil : $0 }
    }

    static func merchantCountryCode() -> String {
        Environment.get("STRIPE_MERCHANT_COUNTRY") ?? "US"
    }

    static func currency() -> String {
        Environment.get("STRIPE_CURRENCY") ?? "usd"
    }

    static func monthlyAmountCents() -> Int {
        Environment.get("STRIPE_TRAINER_MONTHLY_AMOUNT").flatMap(Int.init) ?? 600
    }

    static func annualAmountCents() -> Int {
        Environment.get("STRIPE_TRAINER_ANNUAL_AMOUNT").flatMap(Int.init) ?? 5760
    }

    static func config() -> PaymentConfigDTO {
        PaymentConfigDTO(
            configured: isConfigured() && publishableKey() != nil,
            publishableKey: publishableKey(),
            merchantID: merchantID(),
            merchantCountryCode: merchantCountryCode(),
            monthlyAmount: monthlyAmountCents(),
            annualAmount: annualAmountCents(),
            currency: currency()
        )
    }

    static func createPaymentIntent(
        for user: User,
        payload: CreatePaymentIntentRequest,
        on database: any Database,
        app: Application
    ) async throws -> PaymentIntentDTO {
        guard isConfigured(), let secretKey = Environment.get("STRIPE_SECRET_KEY") else {
            throw Abort(.serviceUnavailable, reason: "Stripe is not configured")
        }
        guard let userID = user.id else { throw Abort(.internalServerError) }

        let currency = (payload.currency ?? currency()).lowercased()
        let (amount, productID, sessionCount) = try await resolvePurchase(
            for: user,
            payload: payload,
            on: database
        )

        var metadata: [String: String] = [
            "user_id": userID.uuidString,
            "product_type": payload.productType,
        ]
        if let productID {
            metadata["product_id"] = productID
        }
        if let plan = payload.plan {
            metadata["plan"] = plan
        }
        if let clientID = payload.clientID {
            metadata["client_id"] = clientID.uuidString
        }
        if let sessionCount {
            metadata["session_count"] = String(sessionCount)
        }

        let stripeResponse = try await postPaymentIntent(
            secretKey: secretKey,
            amount: amount,
            currency: currency,
            metadata: metadata,
            on: app
        )

        let record = StripePayment(
            userID: userID,
            paymentIntentID: stripeResponse.id,
            productType: payload.productType,
            clientID: payload.clientID,
            productID: productID,
            amount: amount,
            currency: currency,
            status: stripeResponse.status,
            sessionCount: sessionCount
        )
        try await record.save(on: database)

        guard let clientSecret = stripeResponse.client_secret else {
            throw Abort(.badGateway, reason: "Stripe did not return a client secret")
        }

        return PaymentIntentDTO(
            clientSecret: clientSecret,
            paymentIntentID: stripeResponse.id,
            amount: amount,
            currency: currency
        )
    }

    static func paymentStatus(
        paymentIntentID: String,
        for user: User,
        on database: any Database,
        app: Application
    ) async throws -> PaymentStatusDTO {
        guard let userID = user.id else { throw Abort(.internalServerError) }

        guard let record = try await StripePayment.query(on: database)
            .filter(\.$paymentIntentID == paymentIntentID)
            .first() else {
            throw Abort(.notFound, reason: "Payment not found")
        }

        if record.$user.id != userID, user.userRole != .admin {
            throw Abort(.forbidden)
        }

        if isConfigured(), let secretKey = Environment.get("STRIPE_SECRET_KEY") {
            let remote = try await fetchPaymentIntent(id: paymentIntentID, secretKey: secretKey, on: app)
            if remote.status != record.status {
                record.status = remote.status
                try await record.save(on: database)
            }
        }

        return PaymentStatusDTO(
            paymentIntentID: paymentIntentID,
            status: record.status,
            fulfilled: record.status == "succeeded"
        )
    }

    static func handleWebhook(
        payload: ByteBuffer,
        signatureHeader: String?,
        on database: any Database,
        app: Application
    ) async throws {
        guard isConfigured(), let webhookSecret = Environment.get("STRIPE_WEBHOOK_SECRET"), !webhookSecret.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "Stripe webhooks are not configured")
        }
        guard let signatureHeader else {
            throw Abort(.badRequest, reason: "Missing Stripe-Signature header")
        }

        let body = Data(payload.readableBytesView)
        guard verifySignature(payload: body, header: signatureHeader, secret: webhookSecret) else {
            throw Abort(.badRequest, reason: "Invalid Stripe webhook signature")
        }

        let event = try JSONDecoder().decode(StripeEvent.self, from: body)
        app.logger.info("Stripe webhook received: \(event.type)")

        switch event.type {
        case "payment_intent.succeeded":
            try await handlePaymentIntentSucceeded(event: event, on: database, app: app)
        case "payment_intent.payment_failed":
            try await handlePaymentIntentFailed(event: event, on: database)
        default:
            break
        }
    }

    // MARK: - Fulfillment

    private static func handlePaymentIntentSucceeded(
        event: StripeEvent,
        on database: any Database,
        app: Application
    ) async throws {
        guard let paymentIntent = event.data.object else { return }
        let paymentIntentID = paymentIntent.id

        if try await StripePayment.query(on: database)
            .filter(\.$stripeEventID == event.id)
            .first() != nil {
            return
        }

        guard let record = try await StripePayment.query(on: database)
            .filter(\.$paymentIntentID == paymentIntentID)
            .first() else {
            app.logger.warning("Stripe payment succeeded but no local record for \(paymentIntentID)")
            return
        }

        record.status = "succeeded"
        record.stripeEventID = event.id
        try await record.save(on: database)

        let metadata = paymentIntent.metadata ?? [:]
        switch record.productType {
        case "trainer_subscription":
            try await fulfillTrainerSubscription(record: record, metadata: metadata, on: database, app: app)
        case "session_package":
            try await fulfillSessionPackage(record: record, metadata: metadata, on: database, app: app)
        default:
            app.logger.warning("Unknown Stripe product type: \(record.productType)")
        }
    }

    private static func handlePaymentIntentFailed(event: StripeEvent, on database: any Database) async throws {
        guard let paymentIntent = event.data.object else { return }
        guard let record = try await StripePayment.query(on: database)
            .filter(\.$paymentIntentID == paymentIntent.id)
            .first() else { return }

        record.status = "failed"
        if record.stripeEventID == nil {
            record.stripeEventID = event.id
        }
        try await record.save(on: database)
    }

    static func fulfillTrainerSubscription(
        record: StripePayment,
        metadata: [String: String],
        on database: any Database,
        app: Application
    ) async throws {
        let userID = record.$user.id
        let productID = record.productID ?? metadata["product_id"] ?? trainerMonthlyProductID
        let plan = metadata["plan"] ?? "monthly"

        let expiresAt: Date
        if plan == "annual" || productID.contains("annual") {
            expiresAt = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        } else {
            expiresAt = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        }

        let originalTransactionID = "stripe:\(record.paymentIntentID)"
        let subscription: Subscription
        if let existing = try await Subscription.query(on: database)
            .filter(\.$originalTransactionID == originalTransactionID)
            .first() {
            existing.productID = productID
            existing.status = "active"
            existing.startedAt = existing.startedAt ?? Date()
            existing.expiresAt = expiresAt
            existing.expiryNotifiedAt = nil
            existing.$user.id = userID
            try await existing.save(on: database)
            subscription = existing
        } else {
            subscription = Subscription(
                userID: userID,
                productID: productID,
                originalTransactionID: originalTransactionID,
                latestReceipt: nil,
                status: "active",
                startedAt: Date(),
                expiresAt: expiresAt
            )
            try await subscription.save(on: database)
        }

        if let user = try await User.find(userID, on: database) {
            await SubscriptionNotificationService.notifyActivated(
                user: user,
                planName: SubscriptionNotificationService.planDisplayName(for: productID),
                expiresAt: expiresAt,
                on: app
            )
        }

        app.logger.info("Fulfilled trainer subscription for user \(userID) via Stripe")
        _ = subscription
    }

    static func fulfillSessionPackage(
        record: StripePayment,
        metadata: [String: String],
        on database: any Database,
        app: Application
    ) async throws {
        guard let clientID = record.clientID ?? metadata["client_id"].flatMap(UUID.init(uuidString:)) else { return }
        let userID = record.$user.id
        guard let user = try await User.find(userID, on: database) else { return }

        let sessionCount = record.sessionCount ?? metadata["session_count"].flatMap(Int.init) ?? 0
        guard sessionCount > 0 else { return }

        let amount = Double(record.amount) / 100.0
        _ = try await FinancialService.createEvent(
            for: user,
            payload: CreateFinancialEventRequest(
                clientID: clientID,
                kind: "income",
                title: "Package Added",
                detail: "Paid via Apple Pay (\(sessionCount) sessions)",
                amount: amount,
                sessionDelta: sessionCount,
                occurredAt: Date()
            ),
            on: database,
            app: app
        )

        app.logger.info("Fulfilled session package for client \(clientID) via Stripe")
    }

    // MARK: - Purchase resolution

    private static func resolvePurchase(
        for user: User,
        payload: CreatePaymentIntentRequest,
        on database: any Database
    ) async throws -> (amount: Int, productID: String?, sessionCount: Int?) {
        switch payload.productType {
        case "trainer_subscription":
            guard user.userRole == .trainer || user.userRole == .admin else {
                throw Abort(.forbidden, reason: "Trainer subscription is only available for trainers")
            }
            let plan = payload.plan?.lowercased() ?? "monthly"
            switch plan {
            case "monthly":
                return (monthlyAmountCents(), trainerMonthlyProductID, nil)
            case "annual":
                return (annualAmountCents(), trainerAnnualProductID, nil)
            default:
                throw Abort(.badRequest, reason: "Unknown subscription plan")
            }

        case "session_package":
            guard user.userRole == .trainer || user.userRole == .admin else {
                throw Abort(.forbidden, reason: "Session packages can only be created by trainers")
            }
            guard let clientID = payload.clientID else {
                throw Abort(.badRequest, reason: "clientID is required for session packages")
            }
            _ = try await ClientAccessService.requireClient(clientID, for: user, on: database)
            guard let amount = payload.amount, amount > 0 else {
                throw Abort(.badRequest, reason: "amount must be greater than zero")
            }
            guard let sessionCount = payload.sessionCount, sessionCount > 0 else {
                throw Abort(.badRequest, reason: "sessionCount must be greater than zero")
            }
            return (amount, nil, sessionCount)

        default:
            throw Abort(.badRequest, reason: "Unknown product type")
        }
    }

    // MARK: - Stripe HTTP

    private struct StripePaymentIntentResponse: Decodable {
        let id: String
        let client_secret: String?
        let status: String
        let metadata: [String: String]?
    }

    private struct StripeEvent: Decodable {
        struct DataContainer: Decodable {
            let object: StripePaymentIntentResponse?
        }

        let id: String
        let type: String
        let data: DataContainer
    }

    private static func postPaymentIntent(
        secretKey: String,
        amount: Int,
        currency: String,
        metadata: [String: String],
        on app: Application
    ) async throws -> StripePaymentIntentResponse {
        var fields: [String] = [
            "amount=\(amount)",
            "currency=\(currency)",
            "payment_method_types[]=card",
        ]
        for (key, value) in metadata {
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            fields.append("metadata[\(encodedKey)]=\(encodedValue)")
        }

        let body = fields.joined(separator: "&")
        let response = try await app.client.post(URI(string: "https://api.stripe.com/v1/payment_intents")) { request in
            request.headers.add(name: .authorization, value: "Bearer \(secretKey)")
            request.headers.add(name: .contentType, value: "application/x-www-form-urlencoded")
            request.body = ByteBuffer(string: body)
        }

        guard response.status == .ok else {
            let errorBody = response.body.map { String(buffer: $0) } ?? "unknown"
            app.logger.error("Stripe create PaymentIntent failed: \(errorBody)")
            throw Abort(.badGateway, reason: "Could not create payment with Stripe")
        }

        return try response.content.decode(StripePaymentIntentResponse.self)
    }

    private static func fetchPaymentIntent(
        id: String,
        secretKey: String,
        on app: Application
    ) async throws -> StripePaymentIntentResponse {
        let response = try await app.client.get(URI(string: "https://api.stripe.com/v1/payment_intents/\(id)")) { request in
            request.headers.add(name: .authorization, value: "Bearer \(secretKey)")
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Could not fetch payment status from Stripe")
        }

        return try response.content.decode(StripePaymentIntentResponse.self)
    }

    // MARK: - Webhook signature

    private static func verifySignature(payload: Data, header: String, secret: String) -> Bool {
        var timestamp: String?
        var signatures: [String] = []

        for part in header.split(separator: ",") {
            let pieces = part.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            let key = String(pieces[0])
            let value = String(pieces[1])
            if key == "t" {
                timestamp = value
            } else if key == "v1" {
                signatures.append(value)
            }
        }

        guard let timestamp, !signatures.isEmpty else { return false }

        if let ts = TimeInterval(timestamp) {
            let age = abs(Date().timeIntervalSince1970 - ts)
            guard age <= 300 else { return false }
        }

        let signedPayload = Data("\(timestamp).".utf8) + payload
        let key = SymmetricKey(data: Data(secret.utf8))
        let expected = HMAC<SHA256>.authenticationCode(for: signedPayload, using: key)
        let expectedHex = Data(expected).map { String(format: "%02x", $0) }.joined()

        return signatures.contains { constantTimeCompare($0, expectedHex) }
    }

    private static func constantTimeCompare(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(lhs.utf8, rhs.utf8) {
            difference |= a ^ b
        }
        return difference == 0
    }
}
