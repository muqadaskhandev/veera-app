import Foundation

struct ClientDTO: Codable {
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
    let injuryHistory: String
    let primaryGoal: String
    let skillLevel: String
    let note: String
    let avatarURL: String?
}

enum ClientLoader {
    static func client(from dto: ClientDTO) -> Client {
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
            injuryHistory: dto.injuryHistory,
            primaryGoal: dto.primaryGoal,
            skillLevel: dto.skillLevel,
            note: dto.note,
            avatarURL: dto.avatarURL
        )
    }
}
