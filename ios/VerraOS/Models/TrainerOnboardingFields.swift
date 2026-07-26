//
//  TrainerOnboardingFields.swift
//  VerraOS
//
//  Shared option lists for trainer onboarding (and Edit Profile).
//  Private keys stay trainer-only; public keys can appear on the client view.
//

import Foundation

enum TrainerOnboardingFields {
    static let gender = "gender"
    static let age = "age"
    static let tenure = "tenure"
    static let location = "location"
    static let clients = "clients"
    static let focus = "focus"
    static let referral = "referral"

    /// Shown on the trainer's own edit screen (all onboarding Q&A).
    static let editableKeys: [String] = [
        gender, age, tenure, location, clients, focus, referral
    ]

    /// Safe to show clients viewing the trainer profile.
    static let clientVisibleKeys: Set<String> = [tenure, location, focus]

    static let genderOptions = ["Male", "Female"]
    static let ageOptions = ["18 – 24", "25 – 34", "35 – 44", "45 – 54", "55+"]
    static let tenureOptions = [
        "Less than 1 year",
        "1 – 3 years",
        "3 – 5 years",
        "5+ years",
    ]
    static let locationOptions = [
        "Commercial Gym",
        "Private / Boutique Studio",
        "Home Gym / Client Homes",
        "Online / Remote Only",
    ]
    static let clientsOptions = [
        "1 – 5 Clients",
        "6 – 15 Clients",
        "16 – 30 Clients",
        "31+ Clients",
    ]
    static let referralOptions = [
        "Word of mouth / Another trainer",
        "Instagram / Social media",
        "Online search",
        "Other",
    ]

    static func title(for key: String) -> String {
        switch key {
        case gender: return "Gender"
        case age: return "Age range"
        case tenure: return "Experience"
        case location: return "Where you train"
        case clients: return "Active clients"
        case focus: return "Primary Coaching Focus"
        case referral: return "How you found Verra"
        default: return key.capitalized
        }
    }

    static func options(for key: String) -> [String] {
        switch key {
        case gender: return genderOptions
        case age: return ageOptions
        case tenure: return tenureOptions
        case location: return locationOptions
        case clients: return clientsOptions
        case focus: return CoachingFocus.allCases.map(\.rawValue)
        case referral: return referralOptions
        default: return []
        }
    }

    static func allowsMultiple(_ key: String) -> Bool {
        key == focus
    }

    static func allowsOtherText(_ key: String) -> Bool {
        key == referral
    }

    static func focusList(from answers: [String: String]) -> [String] {
        guard let raw = answers[focus], !raw.isEmpty else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func encodeFocus(_ selected: Set<String>) -> String {
        selected.sorted().joined(separator: ", ")
    }
}
