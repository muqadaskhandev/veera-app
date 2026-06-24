//
//  TrainerProfile.swift
//  VerraOS
//

import Foundation

/// How often Activity alerts (client workout completions) are delivered.
enum ActivityAlertMode: String, Codable, CaseIterable, Identifiable {
    case everyWorkout
    case personalBests

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyWorkout: return "Every Workout"
        case .personalBests: return "Personal Bests Only"
        }
    }
}

/// Topic options for the Help & Support contact form.
enum SupportTopic: String, Codable, CaseIterable, Identifiable {
    case bug = "Bug"
    case question = "Question"
    case billing = "Billing"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bug: return "ladybug.fill"
        case .question: return "questionmark.circle.fill"
        case .billing: return "creditcard.fill"
        }
    }
}

/// Weight unit preference applied across all weight displays and inputs.
enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kg
    case lbs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kg: return "Kilograms"
        case .lbs: return "Pounds"
        }
    }

    var short: String {
        switch self {
        case .kg: return "kg"
        case .lbs: return "lbs"
        }
    }

    private static let kgPerLb = 0.45359237

    /// Converts a value stored in kilograms into this unit.
    func fromKg(_ kg: Double) -> Double {
        self == .kg ? kg : kg / Self.kgPerLb
    }

    /// Converts a value entered in this unit back into kilograms.
    func toKg(_ value: Double) -> Double {
        self == .kg ? value : value * Self.kgPerLb
    }
}

/// The full set of specialty tags a trainer can advertise on their profile.
enum Specialty: String, Codable, CaseIterable, Identifiable {
    case weightLoss = "Weight Loss"
    case strength = "Strength"
    case rehab = "Rehab"
    case hypertrophy = "Hypertrophy"
    case nutrition = "Nutrition"
    case mobility = "Mobility"
    case conditioning = "Conditioning"
    case powerlifting = "Powerlifting"
    case prenatal = "Prenatal"
    case endurance = "Endurance"

    var id: String { rawValue }
}

/// Persisted trainer account: identity, specialties, and every preference shown
/// in the menu's Settings hub. Encoded as JSON to UserDefaults so it survives
/// app launches.
struct TrainerProfile: Codable, Equatable {
    var name: String
    var title: String
    var bio: String
    var specialties: Set<Specialty>
    /// Raw JPEG/PNG bytes of the chosen avatar, if any.
    var avatarData: Data?

    // Notification preferences
    var notificationsEnabled: Bool
    var notifyMoney: Bool
    var notifySchedule: Bool
    var notifyActivity: Bool
    var activityMode: ActivityAlertMode
    var quietHoursEnabled: Bool
    /// Minutes from midnight for quiet-hours start / end.
    var quietStartMinutes: Int
    var quietEndMinutes: Int

    // Security
    var biometricLoginEnabled: Bool

    // Units (optional for backwards-compatible decoding of older stored profiles)
    var weightUnit: WeightUnit?

    static let `default` = TrainerProfile(
        name: "Jordan Vale",
        title: "Head Strength Coach",
        bio: "Helping driven people get strong, move well, and stay consistent. 10+ years coaching strength and body recomposition.",
        specialties: [.strength, .hypertrophy, .nutrition],
        avatarData: nil,
        notificationsEnabled: true,
        notifyMoney: true,
        notifySchedule: true,
        notifyActivity: true,
        activityMode: .personalBests,
        quietHoursEnabled: true,
        quietStartMinutes: 22 * 60,
        quietEndMinutes: 6 * 60,
        biometricLoginEnabled: false,
        weightUnit: .kg
    )

    /// Initials derived from the display name for the fallback avatar.
    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }
}
