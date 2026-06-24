//
//  NavTab.swift
//  VerraOS
//

import Foundation

/// The four primary destinations in the bottom navigation bar.
enum NavTab: Int, CaseIterable, Identifiable {
    case schedule
    case clients
    case messages
    case financials

    var id: Int { rawValue }

    /// Title shown in the top header for this tab.
    var title: String {
        switch self {
        case .schedule: return "Schedule"
        case .clients: return "Clients"
        case .messages: return "Messages"
        case .financials: return "Financials"
        }
    }

    /// SF Symbol for the inactive (outlined) state.
    var symbol: String {
        switch self {
        case .schedule: return "calendar"
        case .clients: return "person.2"
        case .messages: return "bubble.left.and.bubble.right"
        case .financials: return "chart.bar"
        }
    }

    /// SF Symbol for the active (filled / bold) state.
    var symbolFilled: String {
        switch self {
        case .schedule: return "calendar"
        case .clients: return "person.2.fill"
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .financials: return "chart.bar.fill"
        }
    }

    var label: String {
        switch self {
        case .schedule: return "Schedule"
        case .clients: return "Clients"
        case .messages: return "Messages"
        case .financials: return "Financials"
        }
    }
}
