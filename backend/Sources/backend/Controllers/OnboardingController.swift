import Fluent
import Vapor

struct OnboardingController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let publicOnboarding = routes.grouped("api", "onboarding")
        publicOnboarding.post("invite", "validate", use: validateInvite)

        let onboarding = routes.grouped("api", "onboarding")
            .grouped(JWTAuthMiddleware())

        onboarding.get("status", use: status)

        let trainer = onboarding.grouped(RoleGuardMiddleware(.trainer))
        trainer.get("trainer", use: getTrainerOnboarding)
        trainer.post("trainer", use: saveTrainerOnboarding)

        let client = onboarding.grouped(RoleGuardMiddleware(.client))
        client.post("client", use: completeClientOnboarding)
    }

    @Sendable
    func status(req: Request) async throws -> OnboardingStatusResponse {
        let user = try req.auth.require(User.self)
        return try await OnboardingService.status(for: user, on: req.db)
    }

    @Sendable
    func getTrainerOnboarding(req: Request) async throws -> TrainerOnboardingDTO {
        let user = try req.auth.require(User.self)
        guard let onboarding = try await OnboardingService.trainerOnboarding(for: user, on: req.db) else {
            return TrainerOnboardingDTO(completed: false, answers: [:], completedAt: nil)
        }
        return onboarding
    }

    @Sendable
    func saveTrainerOnboarding(req: Request) async throws -> TrainerOnboardingDTO {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(SaveTrainerOnboardingRequest.self)
        return try await OnboardingService.saveTrainerOnboarding(
            for: user,
            answers: payload.answers,
            markComplete: payload.markComplete ?? false,
            on: req.db
        )
    }

    @Sendable
    func completeClientOnboarding(req: Request) async throws -> ClientDTO {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(ClientOnboardingRequest.self)
        return try await OnboardingService.completeClientOnboarding(for: user, payload: payload, on: req.db)
    }

    @Sendable
    func validateInvite(req: Request) async throws -> ValidateInviteResponse {
        struct ValidateInviteRequest: Content { var code: String }
        let payload = try req.content.decode(ValidateInviteRequest.self)
        return try await InviteService.validate(code: payload.code, on: req.db)
    }
}

extension TrainerOnboardingDTO {
    init(completed: Bool, answers: [String: String], completedAt: Date?) {
        self.completed = completed
        self.answers = answers
        self.completedAt = completedAt
    }
}
