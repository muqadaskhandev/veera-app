import Fluent
import Foundation
import Vapor

enum SubscriptionExpiryScheduler {
    static func processExpiredSubscriptions(on database: any Database, app: Application) async {
        let now = Date()
        let candidates = (try? await Subscription.query(on: database)
            .filter(\.$status == "active")
            .filter(\.$expiresAt != nil)
            .all()) ?? []

        for subscription in candidates {
            guard let expiresAt = subscription.expiresAt, expiresAt <= now else { continue }

            subscription.status = "expired"
            if subscription.expiryNotifiedAt == nil {
                subscription.expiryNotifiedAt = now
                if let user = try? await subscription.$user.get(on: database) {
                    let planName = SubscriptionNotificationService.planDisplayName(for: subscription.productID)
                    await SubscriptionNotificationService.notifyExpired(
                        user: user,
                        planName: planName,
                        expiredAt: expiresAt,
                        on: app
                    )
                }
            }
            try? await subscription.save(on: database)
        }
    }
}
