//
//  Client.swift
//  VerraOS
//

import SwiftUI

/// Lifecycle status for a client on the roster. Drives the color-coded badge
/// shown in the directory list.
enum ClientStatus: String, CaseIterable, Identifiable {
    case active
    case pending
    case paymentDue
    case paused
    case archived
    case expiringSoon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active: return "Active"
        case .pending: return "Pending"
        case .paymentDue: return "Payment Due"
        case .paused: return "Paused"
        case .archived: return "Archived"
        case .expiringSoon: return "Expiring Soon"
        }
    }

    /// Dot / text accent color for the badge.
    var tint: Color {
        switch self {
        case .active: return Color(hex: 0x57C77B)
        case .pending: return Color(hex: 0xE7B83C)
        case .paymentDue: return Theme.Color.danger
        case .paused: return Theme.Color.inkMuted
        case .archived: return Color(hex: 0x55524B)
        case .expiringSoon: return Color(hex: 0xE8893C)
        }
    }

    /// Soft pill background for the badge.
    var soft: Color { tint.opacity(0.15) }

    /// Sort priority — higher = more urgent / surfaced first.
    var priority: Int {
        switch self {
        case .paymentDue: return 5
        case .expiringSoon: return 4
        case .active: return 3
        case .pending: return 2
        case .paused: return 1
        case .archived: return 0
        }
    }
}

/// How the trainer chooses to invite a new client.
enum InviteChannel: String, CaseIterable, Identifiable {
    case email
    case sms
    var id: String { rawValue }
    var label: String { self == .email ? "Email" : "SMS" }
}

/// A client on the trainer's roster. Holds directory info plus the optional
/// pre-fill profile captured at invite time.
struct Client: Identifiable, Hashable {
    let id: UUID
    var name: String
    var initials: String
    /// Remaining pre-paid sessions in the client's package.
    var sessionsRemaining: Int
    /// Days left on the current plan, drives "Expiring Soon".
    var daysLeftOnPlan: Int
    /// Stored lifecycle status (before expiring-soon derivation).
    var status: ClientStatus
    var isArchived: Bool

    // Contact
    var email: String
    var phone: String

    // Optional pre-fill profile
    var age: Int?
    var gender: String
    var heightCm: Int?
    var weightKg: Int?
    var injuryHistory: String
    var primaryGoal: String
    var skillLevel: String

    /// Free-form quick note kept against the client.
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        initials: String,
        sessionsRemaining: Int,
        daysLeftOnPlan: Int = 30,
        status: ClientStatus = .active,
        isArchived: Bool = false,
        email: String = "",
        phone: String = "",
        age: Int? = nil,
        gender: String = "",
        heightCm: Int? = nil,
        weightKg: Int? = nil,
        injuryHistory: String = "",
        primaryGoal: String = "",
        skillLevel: String = "",
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.initials = initials
        self.sessionsRemaining = sessionsRemaining
        self.daysLeftOnPlan = daysLeftOnPlan
        self.status = status
        self.isArchived = isArchived
        self.email = email
        self.phone = phone
        self.age = age
        self.gender = gender
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.injuryHistory = injuryHistory
        self.primaryGoal = primaryGoal
        self.skillLevel = skillLevel
        self.note = note
    }

    /// The badge to display, applying override rules:
    /// Archived wins, then Payment Due, then the expiring-soon derivation for
    /// otherwise-active clients.
    var effectiveStatus: ClientStatus {
        if isArchived { return .archived }
        if status == .paymentDue { return .paymentDue }
        if status == .active, (daysLeftOnPlan < 3 || sessionsRemaining < 2) {
            return .expiringSoon
        }
        return status
    }
}

extension Client {
    /// Formats a centimeter height as US feet-and-inches notation, e.g. 5'9".
    static func formatHeightImperial(cm: Int) -> String {
        let totalInches = Int((Double(cm) / 2.54).rounded())
        let feet = totalInches / 12
        let inches = totalInches % 12
        return "\(feet)'\(inches)\""
    }

    /// Converts feet + inches into centimeters for storage.
    static func cm(fromFeet feet: Int, inches: Int) -> Int {
        Int((Double(feet * 12 + inches) * 2.54).rounded())
    }

    /// The roster starts empty — the trainer builds it by adding real clients.
    static let roster: [Client] = []
}
