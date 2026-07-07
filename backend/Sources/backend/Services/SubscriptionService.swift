import Fluent
import Foundation
import Vapor

enum SubscriptionService {
    private static let productionURL = "https://buy.itunes.apple.com/verifyReceipt"
    private static let sandboxURL = "https://sandbox.itunes.apple.com/verifyReceipt"

    static let allowedProductIDs: Set<String> = [
        "app.rork.hiyjy25oz4yjrbssyotkw.trainer.monthly",
        "app.rork.hiyjy25oz4yjrbssyotkw.trainer.annual",
    ]

    static func validateReceipt(
        for user: User,
        payload: ValidateReceiptRequest,
        on database: any Database,
        app: Application
    ) async throws -> SubscriptionDTO {
        guard user.userRole == .trainer || user.userRole == .admin else {
            throw Abort(.forbidden, reason: "Subscriptions are only available for trainers")
        }
        guard allowedProductIDs.contains(payload.productID) else {
            throw Abort(.badRequest, reason: "Unknown subscription product")
        }
        guard let userID = user.id else { throw Abort(.internalServerError) }

        let sharedSecret = Environment.get("APPLE_IAP_SHARED_SECRET")
        let useSandbox = Environment.get("APPLE_IAP_USE_SANDBOX")?.lowercased() != "false"
        let verifyURL = useSandbox ? sandboxURL : productionURL

        struct VerifyBody: Content {
            let receiptData: String
            let password: String?
            let excludeOldTransactions: Bool
        }

        struct VerifyResponse: Decodable {
            struct ReceiptInfo: Decodable {
                let product_id: String?
                let original_transaction_id: String?
                let purchase_date_ms: String?
                let expires_date_ms: String?
            }

            let status: Int
            let latest_receipt_info: [ReceiptInfo]?
        }

        let response = try await app.client.post(URI(string: verifyURL)) { request in
            try request.content.encode(
                VerifyBody(
                    receiptData: payload.receiptData,
                    password: sharedSecret,
                    excludeOldTransactions: true
                ),
                as: .json
            )
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Could not verify receipt with Apple")
        }

        let decoded = try response.content.decode(VerifyResponse.self)
        guard decoded.status == 0 else {
            throw Abort(.badRequest, reason: "Invalid App Store receipt")
        }

        let match = decoded.latest_receipt_info?.first(where: { $0.product_id == payload.productID })
            ?? decoded.latest_receipt_info?.first

        guard let productID = match?.product_id,
              let originalTransactionID = match?.original_transaction_id else {
            throw Abort(.badRequest, reason: "Receipt did not include subscription info")
        }

        guard allowedProductIDs.contains(productID) else {
            throw Abort(.badRequest, reason: "Receipt product is not a valid trainer subscription")
        }

        let expiresAt = match?.expires_date_ms.flatMap { ms in
            Double(ms).map { Date(timeIntervalSince1970: $0 / 1000) }
        }
        let startedAt = match?.purchase_date_ms.flatMap { ms in
            Double(ms).map { Date(timeIntervalSince1970: $0 / 1000) }
        }

        let status: String
        if let expiresAt, expiresAt > Date() {
            status = "active"
        } else if expiresAt == nil {
            status = "active"
        } else {
            status = "expired"
        }

        let subscription: Subscription
        let previousStatus: String?
        if let existing = try await Subscription.query(on: database)
            .filter(\.$originalTransactionID == originalTransactionID)
            .first() {
            previousStatus = existing.status
            existing.productID = productID
            existing.latestReceipt = payload.receiptData
            existing.status = status
            if existing.startedAt == nil {
                existing.startedAt = startedAt ?? existing.createdAt
            }
            existing.expiresAt = expiresAt
            if status == "active" {
                existing.expiryNotifiedAt = nil
            }
            existing.$user.id = userID
            try await existing.save(on: database)
            subscription = existing
        } else {
            previousStatus = nil
            subscription = Subscription(
                userID: userID,
                productID: productID,
                originalTransactionID: originalTransactionID,
                latestReceipt: payload.receiptData,
                status: status,
                startedAt: startedAt ?? Date(),
                expiresAt: expiresAt
            )
            try await subscription.save(on: database)
        }

        let becameActive = status == "active" && previousStatus != "active"
        if becameActive {
            await SubscriptionNotificationService.notifyActivated(
                user: user,
                planName: SubscriptionNotificationService.planDisplayName(for: productID),
                expiresAt: expiresAt,
                on: app
            )
        }

        return SubscriptionDTO(from: subscription)
    }

    private static func planDisplayName(for productID: String) -> String {
        SubscriptionNotificationService.planDisplayName(for: productID)
    }

    static func current(for user: User, on database: any Database) async throws -> SubscriptionDTO? {
        guard let userID = user.id else { return nil }
        guard let subscription = try await Subscription.query(on: database)
            .filter(\.$user.$id == userID)
            .sort(\.$updatedAt, .descending)
            .first() else {
            return nil
        }
        return SubscriptionDTO(from: subscription)
    }
}
