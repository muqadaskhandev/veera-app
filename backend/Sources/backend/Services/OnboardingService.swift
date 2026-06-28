import Fluent
import Vapor

enum OnboardingService {
    static func saveTrainerOnboarding(
        for user: User,
        answers: [String: String],
        markComplete: Bool,
        on database: any Database
    ) async throws -> TrainerOnboardingDTO {
        guard user.userRole == .trainer else {
            throw Abort(.forbidden, reason: "Only trainers can save trainer onboarding")
        }

        let answersData = try JSONEncoder().encode(answers)
        let answersJSON = String(data: answersData, encoding: .utf8) ?? "{}"

        if let existing = try await TrainerOnboarding.query(on: database)
            .filter(\.$user.$id == user.id!)
            .first() {
            existing.answersJSON = answersJSON
            if markComplete { existing.completedAt = Date() }
            try await existing.save(on: database)
            return try TrainerOnboardingDTO(from: existing)
        }

        let onboarding = TrainerOnboarding(
            userID: try user.requireID(),
            answersJSON: answersJSON,
            completedAt: markComplete ? Date() : nil
        )
        try await onboarding.save(on: database)
        return try TrainerOnboardingDTO(from: onboarding)
    }

    static func trainerOnboarding(for user: User, on database: any Database) async throws -> TrainerOnboardingDTO? {
        guard let onboarding = try await TrainerOnboarding.query(on: database)
            .filter(\.$user.$id == user.id!)
            .first() else {
            return nil
        }
        return try TrainerOnboardingDTO(from: onboarding)
    }

    static func status(for user: User, on database: any Database) async throws -> OnboardingStatusResponse {
        switch user.userRole {
        case .trainer:
            let onboarding = try await trainerOnboarding(for: user, on: database)
            let trainer = try await Trainer.query(on: database).filter(\.$user.$id == user.id!).first()
            return OnboardingStatusResponse(
                role: user.role,
                onboarded: onboarding?.completed == true,
                details: .init(
                    trainerOnboarding: onboarding,
                    linkedTrainerID: trainer?.id,
                    linkedClientID: nil
                )
            )
        case .client:
            let client = try await Client.query(on: database).filter(\.$user.$id == user.id!).first()
            return OnboardingStatusResponse(
                role: user.role,
                onboarded: client != nil,
                details: .init(
                    trainerOnboarding: nil,
                    linkedTrainerID: client?.$trainer.id,
                    linkedClientID: client?.id
                )
            )
        case .admin:
            return OnboardingStatusResponse(role: user.role, onboarded: true, details: nil)
        case .none:
            return OnboardingStatusResponse(role: user.role, onboarded: false, details: nil)
        }
    }

    static func completeClientOnboarding(
        for user: User,
        payload: ClientOnboardingRequest,
        on database: any Database
    ) async throws -> ClientDTO {
        guard user.userRole == .client else {
            throw Abort(.forbidden, reason: "Only clients can complete client onboarding")
        }

        if let existing = try await Client.query(on: database).filter(\.$user.$id == user.id!).first() {
            if let displayName = payload.displayName, !displayName.isEmpty {
                existing.name = displayName
                existing.initials = initials(from: displayName)
            }
            if let goal = payload.primaryGoal {
                existing.primaryGoal = goal
            }
            try await existing.save(on: database)
            return try ClientDTO(from: existing)
        }

        guard let inviteCode = payload.inviteCode, !inviteCode.isEmpty else {
            throw Abort(.badRequest, reason: "Invite code is required")
        }

        let displayName = payload.displayName ?? user.displayName
        try await AuthService.linkClientToInvite(
            user: user,
            inviteCode: inviteCode,
            displayName: displayName,
            primaryGoal: payload.primaryGoal ?? "",
            on: database
        )

        guard let client = try await Client.query(on: database).filter(\.$user.$id == user.id!).first() else {
            throw Abort(.internalServerError, reason: "Client profile was not created")
        }
        return try ClientDTO(from: client)
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }
}
