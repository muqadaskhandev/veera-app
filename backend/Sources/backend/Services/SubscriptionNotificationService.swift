import Fluent
import Foundation
import Vapor

enum SubscriptionNotificationService {
    static func planDisplayName(for productID: String) -> String {
        if productID.contains("annual") { return "Annual" }
        if productID.contains("monthly") { return "Monthly" }
        return "Verra Pro"
    }

    static func notifyActivated(
        user: User,
        planName: String,
        expiresAt: Date?,
        on app: Application
    ) async {
        guard let userID = user.id else { return }

        await UserNotificationDeliveryService.deliver(
            to: userID,
            topic: .money,
            category: "subscription",
            title: "Verra Pro activated",
            body: "Your \(planName) subscription is now active.",
            pushKind: .subscriptionActivated,
            on: app.db,
            app: app
        )

        if let email = user.email {
            await TransactionalEmailService.sendSubscriptionActivated(
                to: email,
                displayName: user.displayName,
                planName: planName,
                expiresAt: expiresAt,
                on: app
            )
        }
    }

    static func notifyExpired(
        user: User,
        planName: String,
        expiredAt: Date?,
        on app: Application
    ) async {
        guard let userID = user.id else { return }

        await UserNotificationDeliveryService.deliver(
            to: userID,
            topic: .money,
            category: "subscription",
            title: "Verra Pro expired",
            body: "Your \(planName) subscription has ended. Renew to keep access.",
            pushKind: .subscriptionExpired,
            on: app.db,
            app: app
        )

        if let email = user.email {
            await TransactionalEmailService.sendSubscriptionExpired(
                to: email,
                displayName: user.displayName,
                planName: planName,
                expiredAt: expiredAt,
                on: app
            )
        }
    }
}
