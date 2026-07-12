import StripePaymentSheet
import UIKit

@MainActor
final class StripePaymentService {
    static let shared = StripePaymentService()

    private var paymentSheet: PaymentSheet?

    func configure(publishableKey: String) {
        STPAPIClient.shared.publishableKey = publishableKey
    }

    func present(
        clientSecret: String,
        merchantID: String,
        merchantCountryCode: String
    ) async throws -> Bool {
        guard let presenter = Self.topViewController() else {
            throw APIError.server("Could not present payment sheet")
        }

        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "Verra"
        configuration.applePay = .init(
            merchantId: merchantID,
            merchantCountryCode: merchantCountryCode
        )
        // Card + Apple Pay only (no Link / bank) — enforced by PaymentIntent payment_method_types
        configuration.allowsDelayedPaymentMethods = false

        let sheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
        paymentSheet = sheet

        return try await withCheckedThrowingContinuation { continuation in
            sheet.present(from: presenter) { result in
                switch result {
                case .completed:
                    continuation.resume(returning: true)
                case .canceled:
                    continuation.resume(returning: false)
                case .failed(let error):
                    continuation.resume(throwing: APIError.server(error.localizedDescription))
                }
            }
        }
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }
}
