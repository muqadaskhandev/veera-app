import Foundation
import UserNotifications

extension Notification.Name {
    static let openChatConversation = Notification.Name("verra.openChatConversation")
}

enum ChatNotificationRouter {
    static func handle(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["conversationID"] as? String,
              let conversationID = UUID(uuidString: raw) else {
            return
        }
        NotificationCenter.default.post(name: .openChatConversation, object: conversationID)
    }
}
