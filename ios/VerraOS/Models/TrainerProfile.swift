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

    /// Formats a kilogram value for display in this unit (e.g. "150 kg" / "330.7 lbs").
    func format(_ kg: Double, fractionDigits: Int = 1) -> String {
        "\(formatNumber(fromKg(kg), fractionDigits: fractionDigits)) \(short)"
    }

    /// Formats a kilogram delta for display in this unit (e.g. "+5 kg" / "−11.0 lbs").
    func formatDelta(_ deltaKg: Double, fractionDigits: Int = 1) -> String {
        let converted = fromKg(deltaKg)
        let sign = converted > 0 ? "+" : (converted < 0 ? "−" : "")
        return "\(sign)\(formatNumber(abs(converted), fractionDigits: fractionDigits)) \(short)"
    }

    /// Digits-only string for text fields (no unit suffix).
    func formatField(_ kg: Double, fractionDigits: Int = 1) -> String {
        formatNumber(fromKg(kg), fractionDigits: fractionDigits)
    }

    private func formatNumber(_ value: Double, fractionDigits: Int) -> String {
        if fractionDigits == 0 || value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.\(fractionDigits)f", value)
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

/// Primary coaching focuses offered during trainer onboarding (multi-select).
enum CoachingFocus: String, Codable, CaseIterable, Identifiable {
    case strengthMuscle = "Strength & Muscle Building"
    case weightLossToning = "Weight Loss & Toning"
    case athleticPerformance = "Athletic Performance"
    case generalHealth = "General Health & Longevity"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .strengthMuscle: return "Hypertrophy and getting stronger"
        case .weightLossToning: return "Fat loss and body composition"
        case .athleticPerformance: return "Speed, power, and sport-specific"
        case .generalHealth: return "Wellness, mobility, and healthy aging"
        }
    }
}

/// Persisted trainer account: identity, specialties, and every preference shown
/// in the menu's Settings hub. Encoded as JSON to UserDefaults so it survives
/// app launches.
struct TrainerProfile: Codable, Equatable {
    var name: String
    var title: String
    var bio: String
    var specialties: Set<Specialty>
    /// Remote avatar path returned by the API, if any.
    var avatarURL: String?
    /// Raw JPEG/PNG bytes of the chosen avatar, if any.
    var avatarData: Data?

    /// Client-visible coaching details (from onboarding).
    var experience: String?
    var trainingLocation: String?
    var coachingFocus: [String]

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

    static let empty = TrainerProfile(
        name: "",
        title: "",
        bio: "",
        specialties: [],
        avatarURL: nil,
        avatarData: nil,
        experience: nil,
        trainingLocation: nil,
        coachingFocus: [],
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

    static let `default` = TrainerProfile(
        name: "Jordan Vale",
        title: "Head Strength Coach",
        bio: "Helping driven people get strong, move well, and stay consistent. 10+ years coaching strength and body recomposition.",
        specialties: [.strength, .hypertrophy, .nutrition],
        avatarURL: nil,
        avatarData: nil,
        experience: "5+ years",
        trainingLocation: "Commercial Gym",
        coachingFocus: [CoachingFocus.strengthMuscle.rawValue],
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

    enum CodingKeys: String, CodingKey {
        case name, title, bio, specialties, avatarURL, avatarData
        case experience, trainingLocation, coachingFocus
        case notificationsEnabled, notifyMoney, notifySchedule, notifyActivity
        case activityMode, quietHoursEnabled, quietStartMinutes, quietEndMinutes
        case biometricLoginEnabled, weightUnit
    }

    init(
        name: String,
        title: String,
        bio: String,
        specialties: Set<Specialty>,
        avatarURL: String?,
        avatarData: Data?,
        experience: String? = nil,
        trainingLocation: String? = nil,
        coachingFocus: [String] = [],
        notificationsEnabled: Bool,
        notifyMoney: Bool,
        notifySchedule: Bool,
        notifyActivity: Bool,
        activityMode: ActivityAlertMode,
        quietHoursEnabled: Bool,
        quietStartMinutes: Int,
        quietEndMinutes: Int,
        biometricLoginEnabled: Bool,
        weightUnit: WeightUnit?
    ) {
        self.name = name
        self.title = title
        self.bio = bio
        self.specialties = specialties
        self.avatarURL = avatarURL
        self.avatarData = avatarData
        self.experience = experience
        self.trainingLocation = trainingLocation
        self.coachingFocus = coachingFocus
        self.notificationsEnabled = notificationsEnabled
        self.notifyMoney = notifyMoney
        self.notifySchedule = notifySchedule
        self.notifyActivity = notifyActivity
        self.activityMode = activityMode
        self.quietHoursEnabled = quietHoursEnabled
        self.quietStartMinutes = quietStartMinutes
        self.quietEndMinutes = quietEndMinutes
        self.biometricLoginEnabled = biometricLoginEnabled
        self.weightUnit = weightUnit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        title = try c.decode(String.self, forKey: .title)
        bio = try c.decode(String.self, forKey: .bio)
        specialties = try c.decode(Set<Specialty>.self, forKey: .specialties)
        avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL)
        avatarData = try c.decodeIfPresent(Data.self, forKey: .avatarData)
        experience = try c.decodeIfPresent(String.self, forKey: .experience)
        trainingLocation = try c.decodeIfPresent(String.self, forKey: .trainingLocation)
        coachingFocus = try c.decodeIfPresent([String].self, forKey: .coachingFocus) ?? []
        notificationsEnabled = try c.decode(Bool.self, forKey: .notificationsEnabled)
        notifyMoney = try c.decode(Bool.self, forKey: .notifyMoney)
        notifySchedule = try c.decode(Bool.self, forKey: .notifySchedule)
        notifyActivity = try c.decode(Bool.self, forKey: .notifyActivity)
        activityMode = try c.decode(ActivityAlertMode.self, forKey: .activityMode)
        quietHoursEnabled = try c.decode(Bool.self, forKey: .quietHoursEnabled)
        quietStartMinutes = try c.decode(Int.self, forKey: .quietStartMinutes)
        quietEndMinutes = try c.decode(Int.self, forKey: .quietEndMinutes)
        biometricLoginEnabled = try c.decode(Bool.self, forKey: .biometricLoginEnabled)
        weightUnit = try c.decodeIfPresent(WeightUnit.self, forKey: .weightUnit)
    }
}
