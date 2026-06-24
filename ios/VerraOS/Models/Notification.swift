//
//  Notification.swift
//  VerraOS
//

import SwiftUI

/// The category of an alert, driving its icon and accent color.
enum NotificationCategory {
    case reminder
    case cancellation
    case lowBalance
    case paymentLogged
    case newMessage

    var symbol: String {
        switch self {
        case .reminder: return "calendar"
        case .cancellation: return "calendar.badge.minus"
        case .lowBalance: return "wallet.bifold"
        case .paymentLogged: return "checkmark.seal.fill"
        case .newMessage: return "bubble.left.fill"
        }
    }

    var tint: Color {
        switch self {
        case .reminder: return Theme.Color.ink
        case .cancellation: return Theme.Color.danger
        case .lowBalance: return Color(hex: 0xE8923D)
        case .paymentLogged: return Color(hex: 0x4FA85C)
        case .newMessage: return Color(hex: 0x3D7FE8)
        }
    }

    /// Background fill for the icon circle.
    var fill: Color { tint.opacity(0.14) }
}

/// A single notification entry in the Notification Center.
struct AppNotification: Identifiable, Hashable {
    let id: UUID
    let category: NotificationCategory
    let title: String
    let detail: String
    /// Minutes ago this alert fired, used for ordering + grouping.
    var minutesAgo: Int
    var isRead: Bool

    init(
        id: UUID = UUID(),
        category: NotificationCategory,
        title: String,
        detail: String,
        minutesAgo: Int,
        isRead: Bool = false
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.minutesAgo = minutesAgo
        self.isRead = isRead
    }

    /// True when the alert fired within the last 24 hours.
    var isToday: Bool { minutesAgo < 60 * 24 }

    /// Relative time label ("2h", "Yesterday", "3d").
    var timeLabel: String {
        if minutesAgo < 1 { return "now" }
        if minutesAgo < 60 { return "\(minutesAgo)m" }
        if minutesAgo < 60 * 24 { return "\(minutesAgo / 60)h" }
        if minutesAgo < 60 * 48 { return "Yesterday" }
        return "\(minutesAgo / (60 * 24))d"
    }
}
