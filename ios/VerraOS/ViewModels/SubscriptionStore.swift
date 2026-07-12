import Foundation

enum SubscriptionPlan: String, CaseIterable, Identifiable {
    case monthly
    case annual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: "Monthly"
        case .annual: "Annual"
        }
    }

    var subtitle: String {
        switch self {
        case .monthly: "Billed every month"
        case .annual: "Save 20% — billed yearly"
        }
    }
}

@Observable
final class SubscriptionStore {
    var hasActiveSubscription = false
    var productID: String?
    var expiresAt: Date?
    var status: String?
    var isAdmin = false
    var isLoading = false
    var paymentConfig: VerraAPI.PaymentConfigDTO?
    var lastError: String?

    var needsPaywall: Bool {
        !isAdmin && !hasActiveSubscription
    }

    var planLabel: String {
        guard let productID else { return "Verra Pro" }
        if productID.contains("annual") { return "Annual" }
        if productID.contains("monthly") { return "Monthly" }
        return "Verra Pro"
    }

    var statusSubtitle: String {
        if isAdmin { return "Admin — full access" }
        if hasActiveSubscription {
            if let expiresAt {
                return "Active until \(expiresAt.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Active subscription"
        }
        return "Subscribe to unlock Verra Pro"
    }

    var stripeConfigured: Bool {
        paymentConfig?.configured == true
    }

    @MainActor
    func bootstrap() async {
        await refreshRole()
        await refreshFromServer()
        await loadPaymentConfig()
    }

    @MainActor
    func refreshRole() async {
        guard let token = AuthStore.accessToken else { return }
        if let user = try? await VerraAPI.me(accessToken: token) {
            isAdmin = user.role == "admin"
            if isAdmin {
                hasActiveSubscription = true
            }
        }
    }

    @MainActor
    func refreshFromServer() async {
        guard let token = AuthStore.accessToken else { return }
        isLoading = true
        defer { isLoading = false }

        if let subscription = await VerraAPI.fetchCurrentSubscription(accessToken: token) {
            apply(subscription)
        } else if !isAdmin {
            hasActiveSubscription = false
            productID = nil
            expiresAt = nil
            status = nil
        }
    }

    @MainActor
    func loadPaymentConfig() async {
        guard let token = AuthStore.accessToken else { return }
        paymentConfig = try? await VerraAPI.fetchPaymentConfig(accessToken: token)
        if let key = paymentConfig?.publishableKey {
            StripePaymentService.shared.configure(publishableKey: key)
        }
    }

    @MainActor
    func purchase(plan: SubscriptionPlan) async throws {
        guard let token = AuthStore.accessToken else {
            throw APIError.server("Not signed in")
        }
        guard let config = paymentConfig, config.configured else {
            throw APIError.server("Payments are not configured on the server")
        }
        guard let merchantID = config.merchantID, !merchantID.isEmpty else {
            throw APIError.server("Apple Pay merchant ID is not configured")
        }

        lastError = nil
        let intent = try await VerraAPI.createPaymentIntent(
            VerraAPI.CreatePaymentIntentBody(
                productType: "trainer_subscription",
                plan: plan.rawValue,
                clientID: nil,
                amount: nil,
                sessionCount: nil,
                currency: config.currency
            ),
            accessToken: token
        )

        let succeeded = try await StripePaymentService.shared.present(
            clientSecret: intent.clientSecret,
            merchantID: merchantID,
            merchantCountryCode: config.merchantCountryCode
        )

        guard succeeded else { return }

        await waitForFulfillment(paymentIntentID: intent.paymentIntentID, accessToken: token)
        await refreshFromServer()
    }

    @MainActor
    private func waitForFulfillment(paymentIntentID: String, accessToken: String) async {
        for _ in 0..<10 {
            if let status = try? await VerraAPI.fetchPaymentStatus(
                paymentIntentID: paymentIntentID,
                accessToken: accessToken
            ), status.fulfilled {
                return
            }
            try? await Task.sleep(for: .milliseconds(800))
        }
    }

    @MainActor
    func priceLabel(for plan: SubscriptionPlan) -> String {
        guard let config = paymentConfig else {
            switch plan {
            case .monthly: return "$6.00"
            case .annual: return "$57.60"
            }
        }
        let cents = plan == .monthly ? config.monthlyAmount : config.annualAmount
        return formatCurrency(cents: cents, currency: config.currency)
    }

    @MainActor
    private func apply(_ subscription: VerraAPI.SubscriptionDTO) {
        hasActiveSubscription = subscription.isActive
        productID = subscription.productID
        expiresAt = subscription.expiresAt
        status = subscription.status
    }

    private func formatCurrency(cents: Int, currency: String) -> String {
        let amount = Double(cents) / 100.0
        let code = currency.uppercased()
        if code == "USD" {
            return String(format: "$%.2f", amount)
        }
        return String(format: "%.2f %@", amount, code)
    }
}
