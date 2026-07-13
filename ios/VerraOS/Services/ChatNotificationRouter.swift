import Foundation
import UserNotifications

extension Notification.Name {
    static let openChatConversation = Notification.Name("verra.openChatConversation")
    static let openScheduleTab = Notification.Name("verra.openScheduleTab")
    static let refreshNotifications = Notification.Name("verra.refreshNotifications")
    /// Fired when a chat message arrives while the user is outside that thread.
    static let incomingChatAlert = Notification.Name("verra.incomingChatAlert")
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

    static func alertCopy(senderName: String, kind: MessageKind) -> (title: String, body: String) {
        let name = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = name.isEmpty ? "someone" : name
        switch kind {
        case .voice:
            return ("Voice message", "You have a new voice message from \(who)")
        case .photo:
            return ("Image", "You have a new image from \(who)")
        case .video:
            return ("Video", "You have a new video from \(who)")
        case .text:
            return ("New message", "You have a new message from \(who)")
        }
    }

    static func postIncomingChatAlert(
        title: String,
        body: String,
        conversationID: UUID? = nil,
        opensSchedule: Bool = false
    ) {
        var info: [String: Any] = [
            "title": title,
            "body": body,
        ]
        if let conversationID {
            info["conversationID"] = conversationID.uuidString
        }
        if opensSchedule {
            info["opensSchedule"] = true
        }

        switch title {
        case "Sessions added", "Package added":
            info["symbol"] = "checkmark.seal.fill"
            info["tintHex"] = NSNumber(value: UInt(0x4FA85C))
        case "New session scheduled":
            info["symbol"] = "calendar.badge.plus"
            info["tintHex"] = NSNumber(value: UInt(0x3D7FE8))
            info["opensSchedule"] = true
        case "Session cancelled":
            info["symbol"] = "calendar.badge.minus"
            info["tintHex"] = NSNumber(value: UInt(0xE08A3C))
            info["opensSchedule"] = true
        case "Session completed":
            info["symbol"] = "checkmark.seal.fill"
            info["tintHex"] = NSNumber(value: UInt(0x4FA85C))
        default:
            break
        }

        NotificationCenter.default.post(
            name: .incomingChatAlert,
            object: nil,
            userInfo: info
        )
    }
}
