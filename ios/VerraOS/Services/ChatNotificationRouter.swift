import Foundation
import UserNotifications

extension Notification.Name {
    static let openChatConversation = Notification.Name("verra.openChatConversation")
    static let openScheduleTab = Notification.Name("verra.openScheduleTab")
    static let refreshNotifications = Notification.Name("verra.refreshNotifications")
}

enum ChatNotificationRouter {
    /// Handles a tapped push notification — may navigate to Messages or Schedule.
    static func handle(userInfo: [AnyHashable: Any]) {
        handle(userInfo: userInfo, navigate: true)
    }

    /// Refreshes the in-app feed when a push arrives in the foreground.
    static func handleForeground(userInfo: [AnyHashable: Any]) {
        handle(userInfo: userInfo, navigate: false)
    }

    private static func handle(userInfo: [AnyHashable: Any], navigate: Bool) {
        if navigate,
           let raw = userInfo["conversationID"] as? String,
           let conversationID = UUID(uuidString: raw) {
            NotificationCenter.default.post(name: .openChatConversation, object: conversationID)
            NotificationCenter.default.post(name: .refreshNotifications, object: nil)
            return
        }

        if navigate, userInfo["sessionID"] != nil {
            NotificationCenter.default.post(name: .openScheduleTab, object: nil)
        }

        NotificationCenter.default.post(name: .refreshNotifications, object: nil)
    }
}
