//
//  TrainerStore.swift
//  VerraOS
//

import SwiftUI

/// Owns the trainer's account profile and all menu preferences, persisting the
/// whole snapshot to UserDefaults so edits survive app launches.
@Observable
final class TrainerStore {
    private static let storageKey = "verra.trainerProfile.v1"

    var profile: TrainerProfile {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(TrainerProfile.self, from: data) {
            profile = decoded
        } else {
            profile = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    // MARK: Convenience

    /// The trainer's chosen weight unit, defaulting to kilograms. Persists via the
    /// profile's `didSet`.
    var units: WeightUnit {
        get { profile.weightUnit ?? .kg }
        set { profile.weightUnit = newValue }
    }

    func toggleSpecialty(_ specialty: Specialty) {
        if profile.specialties.contains(specialty) {
            profile.specialties.remove(specialty)
        } else {
            profile.specialties.insert(specialty)
        }
    }
}
