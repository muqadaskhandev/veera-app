import Fluent
import Vapor

final class StripePayment: Model, @unchecked Sendable {
    static let schema = "stripe_payments"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "payment_intent_id") var paymentIntentID: String
    @OptionalField(key: "stripe_event_id") var stripeEventID: String?
    @Field(key: "product_type") var productType: String
    @OptionalField(key: "client_id") var clientID: UUID?
    @OptionalField(key: "product_id") var productID: String?
    @Field(key: "amount") var amount: Int
    @Field(key: "currency") var currency: String
    @Field(key: "status") var status: String
    @OptionalField(key: "session_count") var sessionCount: Int?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(
        userID: UUID,
        paymentIntentID: String,
        productType: String,
        clientID: UUID? = nil,
        productID: String? = nil,
        amount: Int,
        currency: String,
        status: String = "pending",
        sessionCount: Int? = nil
    ) {
        self.$user.id = userID
        self.paymentIntentID = paymentIntentID
        self.productType = productType
        self.clientID = clientID
        self.productID = productID
        self.amount = amount
        self.currency = currency
        self.status = status
        self.sessionCount = sessionCount
    }
}

struct PaymentConfigDTO: Content {
    let configured: Bool
    let publishableKey: String?
    let merchantID: String?
    let merchantCountryCode: String
    let monthlyAmount: Int
    let annualAmount: Int
    let currency: String
}

struct CreatePaymentIntentRequest: Content {
    var productType: String
    var plan: String?
    var clientID: UUID?
    var amount: Int?
    var sessionCount: Int?
    var currency: String?
}

struct PaymentIntentDTO: Content {
    let clientSecret: String
    let paymentIntentID: String
    let amount: Int
    let currency: String
}

struct PaymentStatusDTO: Content {
    let paymentIntentID: String
    let status: String
    let fulfilled: Bool
}
