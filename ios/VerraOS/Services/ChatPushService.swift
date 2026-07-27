import Foundation
import UIKit
import UserNotifications

enum ChatPushService {
    @MainActor
    static func registerIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }

        await uploadStoredTokenIfPossible()
    }

    static func storeDeviceToken(_ deviceToken: String) {
        UserDefaults.standard.set(deviceToken, forKey: "verra.apns.token")
        Task { @MainActor in
            await uploadStoredTokenIfPossible()
        }
    }

    @MainActor
    private static func uploadStoredTokenIfPossible() async {
        guard let accessToken = AuthStore.accessToken else { return }
        guard let deviceToken = UserDefaults.standard.string(forKey: "verra.apns.token"),
              !deviceToken.isEmpty else { return }
        do {
            try await VerraAPI.registerPushToken(deviceToken, accessToken: accessToken)
        } catch {
            // Keep the stored token — next launch / auth refresh will retry.
        }
    }

    @MainActor
    static func showLocalNotification(
        title: String,
        body: String,
        conversationID: UUID? = nil,
        opensSchedule: Bool = false
    ) {
        // App is open — in-app banner already covers this; avoid a stacked system banner.
        guard UIApplication.shared.applicationState != .active else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var userInfo: [String: Any] = [:]
        if let conversationID {
            userInfo["conversationID"] = conversationID.uuidString
        }
        if opensSchedule {
            userInfo["sessionID"] = "schedule"
        }
        if !userInfo.isEmpty {
            content.userInfo = userInfo
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}
