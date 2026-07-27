import SwiftUI

/// Authenticated client's account profile loaded from the API.
@Observable
final class ClientAccountStore {
    var name = ""
    var email = ""
    var avatarData: Data?
    var avatarURL: String?
    var client: Client?
    var coachProfile = TrainerProfile.empty
    var hasLinkedTrainer = false
    /// This client's own weight display preference (independent of their trainer).
    var weightUnit = "kg"
    var isLoaded = false
    var isSaving = false

    var units: WeightUnit {
        WeightUnit(rawValue: weightUnit) ?? .kg
    }

    @MainActor
    func redeemInvite(code: String) async throws -> String {
        guard let token = AuthStore.accessToken else {
            throw APIError.server("Not signed in")
        }
        let response = try await VerraAPI.redeemInvite(code: code, accessToken: token)
        await ProfileLoader.applyClientProfile(response.profile, to: self)
        return response.message
    }

    @MainActor
    func refreshFromServer() async {
        guard let token = AuthStore.accessToken else { return }
        do {
            let response = try await VerraAPI.fetchProfile(accessToken: token)
            await ProfileLoader.applyClientProfile(response, to: self)
        } catch {
            // Keep existing values when offline.
        }
    }

    /// Persists this client's weight unit only — never touches the trainer's preference.
    @MainActor
    func setWeightUnit(_ unit: WeightUnit) async {
        weightUnit = unit.rawValue
        guard let token = AuthStore.accessToken else { return }
        _ = try? await VerraAPI.updateProfile(
            accessToken: token,
            body: UpdateProfileBody(weightUnit: unit.rawValue)
        )
    }

    @MainActor
    func save(displayName: String, avatarUpload: Data?) async throws {
        try await save(
            displayName: displayName,
            avatarUpload: avatarUpload,
            age: nil,
            heightCm: nil,
            weightKg: nil,
            goalWeightKg: nil
        )
    }

    @MainActor
    func save(
        displayName: String,
        avatarUpload: Data?,
        age: Int?,
        heightCm: Int?,
        weightKg: Int?,
        goalWeightKg: Int?
    ) async throws {
        guard let token = AuthStore.accessToken else {
            throw APIError.server("Not signed in")
        }
        isSaving = true
        defer { isSaving = false }

        if let avatarUpload {
            let response = try await VerraAPI.uploadAvatar(
                imageData: avatarUpload,
                filename: "avatar.jpg",
                mimeType: "image/jpeg",
                accessToken: token
            )
            await ProfileLoader.applyClientProfile(response, to: self)
            if avatarData == nil {
                avatarData = avatarUpload
            }
        }

        let response = try await VerraAPI.updateProfile(
            accessToken: token,
            body: UpdateProfileBody(
                displayName: displayName,
                name: displayName,
                age: age,
                heightCm: heightCm,
                weightKg: weightKg,
                goalWeightKg: goalWeightKg,
                weightUnit: weightUnit
            )
        )
        await ProfileLoader.applyClientProfile(response, to: self)
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }
}
