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
    let injuryHistory: String
    let primaryGoal: String
    let skillLevel: String
    let note: String
}

struct LinkedTrainerDTO: Codable {
    let id: UUID
    let name: String
    let title: String
    let bio: String
    let specialties: [String]
    let avatarURL: String?
}

struct ProfileResponse: Codable {
    let user: ProfileUserDTO
    let profile: ProfileDetailsDTO
    let trainer: ProfileTrainerDTO?
    let client: ProfileClientDTO?
    let linkedTrainer: LinkedTrainerDTO?
}

struct UpdateProfileBody: Encodable {
    var displayName: String?
    var name: String?
    var title: String?
    var bio: String?
    var specialties: [String]?
    var phone: String?
    var primaryGoal: String?
    var gender: String?
    var injuryHistory: String?
    var skillLevel: String?
    var age: Int?
    var heightCm: Int?
    var weightKg: Int?
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
            injuryHistory: dto.injuryHistory,
            primaryGoal: dto.primaryGoal,
            skillLevel: dto.skillLevel,
            note: dto.note
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
