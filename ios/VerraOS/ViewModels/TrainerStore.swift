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

    var isLoadedFromServer = false

    var profile: TrainerProfile {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(TrainerProfile.self, from: data) {
            profile = decoded
        } else {
            profile = .empty
        }
    }

    @MainActor
    func refreshFromServer() async {
        guard let token = AuthStore.accessToken else { return }
        do {
            let response = try await VerraAPI.fetchProfile(accessToken: token)
            await ProfileLoader.applyTrainer(response, to: self)
        } catch {
            // Keep cached profile when offline.
        }
    }

    @MainActor
    func saveToServer(avatarUpload: Data?) async throws {
        guard let token = AuthStore.accessToken else {
            throw APIError.server("Not signed in")
        }

        if let avatarUpload {
            let response = try await VerraAPI.uploadAvatar(
                imageData: avatarUpload,
                filename: "avatar.jpg",
                mimeType: "image/jpeg",
                accessToken: token
            )
            await ProfileLoader.applyTrainer(response, to: self)
        }

        let response = try await VerraAPI.updateProfile(
            accessToken: token,
            body: UpdateProfileBody(
                displayName: profile.name,
                name: profile.name,
                title: profile.title,
                bio: profile.bio,
                specialties: profile.specialties.map(\.rawValue).sorted()
            )
        )
        await ProfileLoader.applyTrainer(response, to: self)
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
