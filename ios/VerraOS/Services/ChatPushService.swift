import Foundation
import UIKit
import UserNotifications

enum ChatPushService {
    @MainActor
    static func registerIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return
        }

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }

        guard let token = AuthStore.accessToken else { return }
        if let stored = UserDefaults.standard.string(forKey: "verra.apns.token"), !stored.isEmpty {
            try? await VerraAPI.registerPushToken(stored, accessToken: token)
        }
    }

    static func storeDeviceToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: "verra.apns.token")
        Task { @MainActor in
            guard let accessToken = AuthStore.accessToken else { return }
            try? await VerraAPI.registerPushToken(token, accessToken: token)
        }
    }

    @MainActor
    static func showLocalNotification(title: String, body: String, conversationID: UUID? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let conversationID {
            content.userInfo = ["conversationID": conversationID.uuidString]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}
