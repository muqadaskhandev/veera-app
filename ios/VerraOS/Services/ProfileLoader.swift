import Foundation
import UIKit

struct ProfileUserDTO: Codable {
    let id: UUID
    let email: String?
    let role: String
    let displayName: String
    let avatarURL: String?
}

struct ProfileDetailsDTO: Codable {
    let displayName: String
    let title: String
    let bio: String
    let specialties: [String]
    let avatarURL: String?
}

struct ProfileTrainerDTO: Codable {
    let id: UUID
    let name: String
    let title: String
    let bio: String
    let specialties: [String]
}

struct ProfileClientDTO: Codable {
    let id: UUID
    let trainerID: UUID
    let name: String
    let initials: String
    let sessionsRemaining: Int
    let daysLeftOnPlan: Int
    let status: String
    let isArchived: Bool
    let email: String
    let phone: String
    let age: Int?
    let gender: String
    let heightCm: Int?
    let weightKg: Int?
    let goalWeightKg: Int?
    let startWeightKg: Double?
    let injuryHistory: String
    let primaryGoal: String
    let skillLevel: String
    let note: String
    let avatarURL: String?
    let visibleModules: [String]?
}

struct LinkedTrainerDTO: Codable {
    let id: UUID
    let name: String
    let title: String
    let bio: String
    let specialties: [String]
    let avatarURL: String?
}

struct ProfileSettingsDTO: Codable {
    let weightUnit: String
    let biometricLoginEnabled: Bool
    let calendarPrefsJSON: String?
}

struct ProfileResponse: Codable {
    let user: ProfileUserDTO
    let profile: ProfileDetailsDTO
    let settings: ProfileSettingsDTO
    let trainer: ProfileTrainerDTO?
    let client: ProfileClientDTO?
    let linkedTrainer: LinkedTrainerDTO?
}

struct UpdateProfileBody: Encodable {
    var displayName: String? = nil
    var name: String? = nil
    var title: String? = nil
    var bio: String? = nil
    var specialties: [String]? = nil
    var phone: String? = nil
    var primaryGoal: String? = nil
    var gender: String? = nil
    var injuryHistory: String? = nil
    var skillLevel: String? = nil
    var age: Int? = nil
    var heightCm: Int? = nil
    var weightKg: Int? = nil
    var goalWeightKg: Int? = nil
    var weightUnit: String? = nil
    var biometricLoginEnabled: Bool? = nil
    var calendarPrefsJSON: String? = nil
}

enum ProfileLoader {
    @MainActor
    static func applyTrainer(_ response: ProfileResponse, to store: TrainerStore) async {
        let details = response.profile
        store.profile.name = details.displayName
        store.profile.title = details.title
        store.profile.bio = details.bio
        store.profile.specialties = Set(
            details.specialties.compactMap { Specialty(rawValue: $0) }
        )
        store.profile.avatarURL = details.avatarURL ?? response.user.avatarURL
        store.profile.avatarData = await downloadAvatar(path: store.profile.avatarURL)
        store.profile.weightUnit = WeightUnit(rawValue: response.settings.weightUnit) ?? .kg
        store.profile.biometricLoginEnabled = response.settings.biometricLoginEnabled
        store.calendarPrefsJSON = response.settings.calendarPrefsJSON
        store.isLoadedFromServer = true
    }

    @MainActor
    static func trainerProfile(from linked: LinkedTrainerDTO) async -> TrainerProfile {
        var profile = TrainerProfile.empty
        profile.name = linked.name
        profile.title = linked.title
        profile.bio = linked.bio
        profile.specialties = Set(linked.specialties.compactMap { Specialty(rawValue: $0) })
        profile.avatarURL = linked.avatarURL
        profile.avatarData = await downloadAvatar(path: linked.avatarURL)
        return profile
    }

    @MainActor
    static func applyClientProfile(_ response: ProfileResponse, to account: ClientAccountStore) async {
        let details = response.profile
        account.name = details.displayName
        account.email = response.user.email ?? account.email
        account.avatarURL = details.avatarURL ?? response.user.avatarURL
        account.avatarData = await downloadAvatar(path: account.avatarURL)
        if let clientDTO = response.client {
            account.client = client(from: clientDTO)
        }
        if let linked = response.linkedTrainer {
            account.coachProfile = await trainerProfile(from: linked)
        } else {
            account.coachProfile = TrainerProfile.empty
        }
        account.hasLinkedTrainer = response.linkedTrainer != nil
        account.weightUnit = response.settings.weightUnit
        account.isLoaded = true
    }

    static func client(from dto: ProfileClientDTO) -> Client {
        Client(
            id: dto.id,
            name: dto.name,
            initials: dto.initials,
            sessionsRemaining: dto.sessionsRemaining,
            daysLeftOnPlan: dto.daysLeftOnPlan,
            status: ClientStatus(rawValue: dto.status) ?? .active,
            isArchived: dto.isArchived,
            email: dto.email,
            phone: dto.phone,
            age: dto.age,
            gender: dto.gender,
            heightCm: dto.heightCm,
            weightKg: dto.weightKg,
            goalWeightKg: dto.goalWeightKg,
            startWeightKg: dto.startWeightKg,
            injuryHistory: dto.injuryHistory,
            primaryGoal: dto.primaryGoal,
            skillLevel: dto.skillLevel,
            note: dto.note,
            avatarURL: dto.avatarURL,
            visibleModules: dto.visibleModules
        )
    }

    static func downloadAvatar(path: String?) async -> Data? {
        guard let path, let url = URL(string: path, relativeTo: APIConfig.baseURL) else {
            return nil
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
