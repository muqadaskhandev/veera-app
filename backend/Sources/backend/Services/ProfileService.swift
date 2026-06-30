import Fluent
import Foundation
import Vapor

struct ProfileUserDTO: Content {
    let id: UUID
    let email: String?
    let role: String
    let displayName: String
    let avatarURL: String?

    init(from user: User, profile: Profile) {
        self.id = user.id!
        self.email = user.email
        self.role = user.role
        self.displayName = profile.displayName
        self.avatarURL = AvatarService.publicURL(
            for: profile.avatarPath,
            cacheVersion: Self.cacheVersion(from: profile)
        )
    }

    private static func cacheVersion(from profile: Profile) -> String? {
        profile.updatedAt.map { String(Int($0.timeIntervalSince1970)) }
    }
}

struct ProfileTrainerDTO: Content {
    let id: UUID
    let name: String
    let title: String
    let bio: String
    let specialties: [String]

    init(from trainer: Trainer) throws {
        self.id = try trainer.requireID()
        self.name = trainer.name
        self.title = trainer.title
        self.bio = trainer.bio
        self.specialties = TrainerSpecialties.decode(trainer.specialtiesJSON)
    }
}

struct ProfileResponse: Content {
    let user: ProfileUserDTO
    let profile: ProfileDetailsDTO
    let trainer: ProfileTrainerDTO?
    let client: ClientDTO?
    let linkedTrainer: TrainerDTO?
}

struct UpdateProfileRequest: Content {
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

enum ProfileService {
    static func getOrCreate(for user: User, on database: any Database) async throws -> Profile {
        if let existing = try await Profile.query(on: database)
            .filter(\.$user.$id == user.id!)
            .first() {
            return existing
        }

        var title = ""
        if user.userRole == .trainer {
            title = "Strength Coach"
        }

        let profile = Profile(
            userID: try user.requireID(),
            displayName: user.displayName,
            title: title,
            bio: "",
            specialtiesJSON: "[]",
            avatarPath: user.avatarPath
        )
        try await profile.save(on: database)
        return profile
    }

    static func load(for user: User, on database: any Database) async throws -> ProfileResponse {
        let profile = try await getOrCreate(for: user, on: database)

        switch user.userRole {
        case .trainer:
            let trainer = try await Trainer.query(on: database)
                .filter(\.$user.$id == user.id!)
                .first()
            return ProfileResponse(
                user: ProfileUserDTO(from: user, profile: profile),
                profile: ProfileDetailsDTO(from: profile),
                trainer: try trainer.map(ProfileTrainerDTO.init),
                client: nil,
                linkedTrainer: nil
            )
        case .client:
            let client = try await Client.query(on: database)
                .filter(\.$user.$id == user.id!)
                .first()
            var linkedTrainer: TrainerDTO?
            if let client, let trainer = try await Trainer.find(client.$trainer.id, on: database) {
                linkedTrainer = try await trainerDTO(for: trainer, on: database)
            }
            return ProfileResponse(
                user: ProfileUserDTO(from: user, profile: profile),
                profile: ProfileDetailsDTO(from: profile),
                trainer: nil,
                client: try client.map(ClientDTO.init),
                linkedTrainer: linkedTrainer
            )
        case .admin, .none:
            return ProfileResponse(
                user: ProfileUserDTO(from: user, profile: profile),
                profile: ProfileDetailsDTO(from: profile),
                trainer: nil,
                client: nil,
                linkedTrainer: nil
            )
        }
    }

    static func update(
        for user: User,
        payload: UpdateProfileRequest,
        on database: any Database
    ) async throws -> ProfileResponse {
        let profile = try await getOrCreate(for: user, on: database)

        let resolvedName = payload.displayName ?? payload.name
        if let name = resolvedName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            profile.displayName = name
            user.displayName = name
        }
        if let title = payload.title { profile.title = title }
        if let bio = payload.bio { profile.bio = bio }
        if let specialties = payload.specialties {
            profile.specialtiesJSON = TrainerSpecialties.encode(specialties)
        }

        try await profile.save(on: database)
        try await user.save(on: database)

        switch user.userRole {
        case .trainer:
            try await syncTrainerTables(for: user, profile: profile, on: database)
        case .client:
            try await syncClientTables(for: user, profile: profile, payload: payload, on: database)
        case .admin, .none:
            break
        }

        return try await load(for: user, on: database)
    }

    static func trainerDTO(for trainer: Trainer, on database: any Database) async throws -> TrainerDTO {
        let trainerID = try trainer.requireID()
        if let trainerUser = try await trainer.$user.get(on: database),
           let userID = trainerUser.id,
           let profile = try await Profile.query(on: database)
            .filter(\.$user.$id == userID)
            .first() {
            return TrainerDTO(
                id: trainerID,
                name: profile.displayName,
                title: profile.title,
                bio: profile.bio,
                specialties: TrainerSpecialties.decode(profile.specialtiesJSON),
                avatarURL: AvatarService.publicURL(
                    for: profile.avatarPath,
                    cacheVersion: profile.updatedAt.map { String(Int($0.timeIntervalSince1970)) }
                )
            )
        }
        return try TrainerDTO(from: trainer)
    }

    private static func syncTrainerTables(
        for user: User,
        profile: Profile,
        on database: any Database
    ) async throws {
        let trainer = try await getOrCreateTrainer(for: user, profile: profile, on: database)

        trainer.name = profile.displayName
        trainer.title = profile.title
        trainer.bio = profile.bio
        trainer.specialtiesJSON = profile.specialtiesJSON
        try await trainer.save(on: database)
    }

    private static func getOrCreateTrainer(
        for user: User,
        profile: Profile,
        on database: any Database
    ) async throws -> Trainer {
        if let existing = try await Trainer.query(on: database)
            .filter(\.$user.$id == user.id!)
            .first() {
            return existing
        }

        let trainer = Trainer(
            name: profile.displayName,
            title: profile.title.isEmpty ? "Strength Coach" : profile.title,
            bio: profile.bio
        )
        trainer.$user.id = try user.requireID()
        trainer.specialtiesJSON = profile.specialtiesJSON
        try await trainer.save(on: database)
        return trainer
    }

    private static func syncClientTables(
        for user: User,
        profile: Profile,
        payload: UpdateProfileRequest,
        on database: any Database
    ) async throws {
        let client = try await getOrCreateClient(for: user, profile: profile, on: database)

        client.name = profile.displayName
        client.initials = initials(from: profile.displayName)
        if client.email.isEmpty, let email = user.email {
            client.email = email
        }

        if let phone = payload.phone { client.phone = phone }
        if let primaryGoal = payload.primaryGoal { client.primaryGoal = primaryGoal }
        if let gender = payload.gender { client.gender = gender }
        if let injuryHistory = payload.injuryHistory { client.injuryHistory = injuryHistory }
        if let skillLevel = payload.skillLevel { client.skillLevel = skillLevel }
        if let age = payload.age { client.age = age }
        if let heightCm = payload.heightCm { client.heightCm = heightCm }
        if let weightKg = payload.weightKg { client.weightKg = weightKg }

        try await client.save(on: database)
    }

    private static func getOrCreateClient(
        for user: User,
        profile: Profile,
        on database: any Database
    ) async throws -> Client {
        if let existing = try await Client.query(on: database)
            .filter(\.$user.$id == user.id!)
            .first() {
            return existing
        }

        let trainer = try await TrainerService.defaultTrainer(on: database)
        let client = Client(
            trainerID: try trainer.requireID(),
            name: profile.displayName,
            initials: initials(from: profile.displayName),
            sessionsRemaining: 0,
            status: "active",
            email: user.email ?? ""
        )
        client.$user.id = try user.requireID()
        try await client.save(on: database)
        return client
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }
}
